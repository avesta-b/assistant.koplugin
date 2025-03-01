--[[--
Displays some text in a scrollable view.

@usage
    local chatgptviewer = ChatGPTViewer:new{
        title = _("I can scroll!"),
        text = _("I'll need to be longer than this example to scroll."),
    }
    UIManager:show(chatgptviewer)
]]
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local CheckButton = require("ui/widget/checkbutton")
local Device = require("device")
local Event = require("ui/event")
local Geom = require("ui/geometry")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local MovableContainer = require("ui/widget/container/movablecontainer")
local Notification = require("ui/widget/notification")
local ScrollTextWidget = require("ui/widget/scrolltextwidget")
local Size = require("ui/size")
local TitleBar = require("ui/widget/titlebar")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local T = require("ffi/util").template
local util = require("util")
local _ = require("gettext")
local InfoMessage = require("ui/widget/infomessage")
local Screen = Device.screen
local configuration = require("configuration")

local ChatGPTViewer = InputContainer:extend {
    title = nil,
    text = nil,
    width = nil,
    height = nil,
    buttons_table = nil,
    -- See TextBoxWidget for details about these options
    -- We default to justified and auto_para_direction to adapt
    -- to any kind of text we are given (book descriptions,
    -- bookmarks' text, translation results...).
    -- When used to display more technical text (HTML, CSS,
    -- application logs...), it's best to reset them to false.
    alignment = "left",
    justified = true,
    lang = nil,
    para_direction_rtl = nil,
    auto_para_direction = true,
    alignment_strict = false,

    title_face = nil,               -- use default from TitleBar
    title_multilines = nil,         -- see TitleBar for details
    title_shrink_font_to_fit = nil, -- see TitleBar for details
    text_face = Font:getFace("x_smallinfofont"),
    fgcolor = Blitbuffer.COLOR_BLACK,
    text_padding = Size.padding.large,
    text_margin = Size.margin.small,
    button_padding = Size.padding.default,
    -- Bottom row with Close, Find buttons. Also added when no caller's buttons defined.
    add_default_buttons = nil,
    default_hold_callback = nil,   -- on each default button
    find_centered_lines_count = 5, -- line with find results to be not far from the center

    onAskQuestion = nil,
    input_dialog = nil,
    showAskQuestion = true,
}

-- Global variables
local active_chatgpt_viewer = nil
local is_input_dialog_open = false

function ChatGPTViewer:init()
    -- calculate window dimension
    self.align = "center"
    self.region = Geom:new {
        x = 0, y = 0,
        w = Screen:getWidth(),
        h = Screen:getHeight(),
    }
    self.width = self.width or Screen:getWidth() - Screen:scaleBySize(30)
    self.height = self.height or Screen:getHeight() - Screen:scaleBySize(30)

    self._find_next = false
    self._find_next_button = false
    self._old_virtual_line_num = 1

    if Device:hasKeys() then
        self.key_events.Close = { { Device.input.group.Back } }
    end

    if Device:isTouchDevice() then
        local range = Geom:new {
            x = 0, y = 0,
            w = Screen:getWidth(),
            h = Screen:getHeight(),
        }
        self.ges_events = {
            TapClose = {
                GestureRange:new {
                    ges = "tap",
                    range = range,
                },
            },
            Swipe = {
                GestureRange:new {
                    ges = "swipe",
                    range = range,
                },
            },
            MultiSwipe = {
                GestureRange:new {
                    ges = "multiswipe",
                    range = range,
                },
            },
            -- Allow selection of one or more words (see textboxwidget.lua):
            HoldStartText = {
                GestureRange:new {
                    ges = "hold",
                    range = range,
                },
            },
            HoldPanText = {
                GestureRange:new {
                    ges = "hold",
                    range = range,
                },
            },
            HoldReleaseText = {
                GestureRange:new {
                    ges = "hold_release",
                    range = range,
                },
                -- callback function when HoldReleaseText is handled as args
                args = function(text, hold_duration, start_idx, end_idx, to_source_index_func)
                    self:handleTextSelection(text, hold_duration, start_idx, end_idx, to_source_index_func)
                end
            },
            -- These will be forwarded to MovableContainer after some checks
            ForwardingTouch = { GestureRange:new { ges = "touch", range = range, }, },
            ForwardingPan = { GestureRange:new { ges = "pan", range = range, }, },
            ForwardingPanRelease = { GestureRange:new { ges = "pan_release", range = range, }, },
        }
    end

    -- If another ChatGPTViewer is open, close it
    if active_chatgpt_viewer and active_chatgpt_viewer ~= self then
        UIManager:close(active_chatgpt_viewer)
    end

    active_chatgpt_viewer = self

    local titlebar = TitleBar:new {
        width = self.width,
        align = "left",
        with_bottom_line = true,
        title = "Assistant: " .. (self.title or ""),
        title_face = self.title_face,
        title_multilines = self.title_multilines,
        title_shrink_font_to_fit = self.title_shrink_font_to_fit,
        close_callback = function() self:onClose() end,
        show_parent = self,
    }

    -- Callback to enable/disable buttons, for at-top/at-bottom feedback
    local prev_at_top = false -- Buttons were created enabled
    local prev_at_bottom = false
    local function button_update(id, enable)
        local button = self.button_table:getButtonById(id)
        if button then
            if enable then
                button:enable()
            else
                button:disable()
            end
            button:refresh()
        end
    end
    self._buttons_scroll_callback = function(low, high)
        if prev_at_top and low > 0 then
            button_update("top", true)
            prev_at_top = false
        elseif not prev_at_top and low <= 0 then
            button_update("top", false)
            prev_at_top = true
        end
        if prev_at_bottom and high < 1 then
            button_update("bottom", true)
            prev_at_bottom = false
        elseif not prev_at_bottom and high >= 1 then
            button_update("bottom", false)
            prev_at_bottom = true
        end
    end

    -- buttons
    local default_buttons = {}

    -- Only add Ask Another Question button if showAskQuestion is true
    if self.showAskQuestion ~= false then
        table.insert(default_buttons, {
            text = _("Ask Another Question"),
            id = "ask_another_question",
            callback = function()
                self:askAnotherQuestion()
            end,
        })
    end

    -- Add the rest of the default buttons
    table.insert(default_buttons, {
        text = "⇱",
        id = "top",
        callback = function()
            self.scroll_text_w:scrollToTop()
        end,
        hold_callback = self.default_hold_callback,
        allow_hold_when_disabled = true,
    })

    table.insert(default_buttons, {
        text = "⇲",
        id = "bottom",
        callback = function()
            self.scroll_text_w:scrollToBottom()
        end,
        hold_callback = self.default_hold_callback,
        allow_hold_when_disabled = true,
    })

    table.insert(default_buttons, {
        text = _("Close"),
        id = "close",
        callback = function()
            self:onClose()
        end,
        hold_callback = self.default_hold_callback,
    })

    local buttons = self.buttons_table or {}
    if self.add_default_buttons or not self.buttons_table then
        table.insert(buttons, default_buttons)
    end

    -- Add a copy button to the bottom button row
    local copy_button = {
        text = _("Copy"),
        callback = function()
            if self.text and self.text ~= "" then
                Device.input.setClipboardText(self.text)
                UIManager:show(InfoMessage:new {
                    text = _("Text copied to clipboard"),
                    timeout = 3,
                })
            end
        end
    }

    -- Insert the buttons into the existing buttons, with close button on the right
    table.insert(buttons[#buttons], copy_button)

    -- Add a button to add notes
    local function createAddNoteButton(self)
        return {
            text = _("Add Note"),
            callback = function()
                -- Check if ui is available in self
                local ui = self.ui
                if not ui or not ui.highlight then
                    UIManager:show(InfoMessage:new {
                        text = _("Highlight functionality not available"),
                        timeout = 1
                    })
                    return
                end

                if not self.text or self.text == "" then
                    UIManager:show(InfoMessage:new {
                        text = _("No text to add as note"),
                        timeout = 1
                    })
                    return
                end

                -- Get the selected text
                local selected_text = self.highlighted_text or ""

                -- Remove the selected text from the full text with multiple strategies
                local note_text = self.text

                -- First, try to remove only if the selected text is after "Highlighted text: "
                local highlighted_start, highlighted_end = note_text:find('Highlighted text: "([^"]*)"')
                if highlighted_start then
                    local highlighted_part = note_text:sub(highlighted_start, highlighted_end)
                    local selected_text_in_highlight = highlighted_part:match('"([^"]*)"')

                    if selected_text_in_highlight == selected_text then
                        note_text = note_text:gsub(
                            'Highlighted text: "' .. selected_text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. '"',
                            "")
                    end
                end

                -- Trim whitespace
                note_text = note_text:gsub("^%s+", ""):gsub("%s+$", "")

                if note_text == "" then
                    UIManager:show(InfoMessage:new {
                        text = _("No text left to add as note"),
                        timeout = 1
                    })
                    return
                end

                local index = ui.highlight:saveHighlight(true)
                local a = ui.annotation.annotations[index]
                a.note = note_text
                ui:handleEvent(Event:new("AnnotationsModified",
                    { a, nb_highlights_added = -1, nb_notes_added = 1 }))

                UIManager:show(InfoMessage:new {
                    text = _("Note added successfully"),
                    timeout = 1
                })
            end
        }
    end

    -- Only add Add Note button if ui context is available
    if self.ui and configuration.features.automatically_add_note == false then
        local add_note_button = createAddNoteButton(self)
        table.insert(buttons[#buttons], add_note_button)
    end

    self.button_table = ButtonTable:new {
        width = self.width - 2 * self.button_padding,
        buttons = buttons,
        zero_sep = true,
        show_parent = self,
    }

    local textw_height = self.height - titlebar:getHeight() - self.button_table:getSize().h

    self.scroll_text_w = ScrollTextWidget:new {
        text = self.text,
        face = self.text_face,
        fgcolor = self.fgcolor,
        width = self.width - 2 * self.text_padding - 2 * self.text_margin,
        height = textw_height - 2 * self.text_padding - 2 * self.text_margin,
        dialog = self,
        alignment = self.alignment,
        justified = self.justified,
        lang = self.lang,
        para_direction_rtl = self.para_direction_rtl,
        auto_para_direction = self.auto_para_direction,
        alignment_strict = self.alignment_strict,
        scroll_callback = self._buttons_scroll_callback,
    }
    self.textw = FrameContainer:new {
        padding = self.text_padding,
        margin = self.text_margin,
        bordersize = 0,
        self.scroll_text_w
    }

    self.frame = FrameContainer:new {
        radius = Size.radius.window,
        padding = 0,
        margin = 0,
        background = Blitbuffer.COLOR_WHITE,
        VerticalGroup:new {
            titlebar,
            CenterContainer:new {
                dimen = Geom:new {
                    w = self.width,
                    h = self.textw:getSize().h,
                },
                self.textw,
            },
            CenterContainer:new {
                dimen = Geom:new {
                    w = self.width,
                    h = self.button_table:getSize().h,
                },
                self.button_table,
            }
        }
    }
    self.movable = MovableContainer:new {
        -- We'll handle these events ourselves, and call appropriate
        -- MovableContainer's methods when we didn't process the event
        ignore_events = {
            -- These have effects over the text widget, and may
            -- or may not be processed by it
            "swipe", "hold", "hold_release", "hold_pan",
            -- These do not have direct effect over the text widget,
            -- but may happen while selecting text: we need to check
            -- a few things before forwarding them
            "touch", "pan", "pan_release",
        },
        self.frame,
    }
    self[1] = WidgetContainer:new {
        align = self.align,
        dimen = self.region,
        self.movable,
    }
end

function ChatGPTViewer:onCloseWidget()
    local function addNote()
        -- Check if ui is available in self
        local ui = self.ui
        if not ui or not ui.highlight or not self.text or self.text == "" then
            return
        end

        -- Get the selected text
        local selected_text = self.highlighted_text or ""

        -- Remove the selected text from the full text with multiple strategies
        local note_text = self.text

        -- First, try to remove only if the selected text is after "Highlighted text: "
        local highlighted_start, highlighted_end = note_text:find('Highlighted text: "([^"]*)"')
        if highlighted_start then
            local highlighted_part = note_text:sub(highlighted_start, highlighted_end)
            local selected_text_in_highlight = highlighted_part:match('"([^"]*)"')

            if selected_text_in_highlight == selected_text then
                note_text = note_text:gsub(
                    'Highlighted text: "' .. selected_text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1") .. '"', "")
            end
        end

        -- Trim whitespace
        note_text = note_text:gsub("^%s+", ""):gsub("%s+$", "")

        if note_text == "" then
            -- No text left to add as a note
            return
        end

        local index = ui.highlight:saveHighlight(true)
        local a = ui.annotation.annotations[index]
        a.note = note_text
        ui:handleEvent(Event:new("AnnotationsModified",
            { a, nb_highlights_added = -1, nb_notes_added = 1 }))
    end
    if self.ui and configuration and configuration.features and configuration.features.automatically_add_note then
        addNote(self)
    end
    -- Reset all history and context
    self.text = ""
    self.message_history = nil
    self.highlighted_text = nil

    -- Reset the active window
    if active_chatgpt_viewer == self then
        active_chatgpt_viewer = nil
    end

    -- Call InputContainer's default onCloseWidget method
    if InputContainer.onCloseWidget then
        InputContainer.onCloseWidget(self)
    end
end

function ChatGPTViewer:askAnotherQuestion()
    -- Prevent multiple dialogs
    if self.input_dialog and self.input_dialog.dialog_open then
        return
    end

    -- Attempt to load configuration
    local success, CONFIGURATION = pcall(function() return require("configuration") end)

    -- Initialize default options
    local default_options = {}

    -- Load additional prompts from configuration if available
    if success and CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.prompts then
        -- Create a sorted list of prompts
        local sorted_prompts = {}
        for prompt_key, prompt_config in pairs(CONFIGURATION.features.prompts) do
            table.insert(sorted_prompts, { key = prompt_key, config = prompt_config })
        end
        -- Sort by order value, default to 1000 if not specified
        table.sort(sorted_prompts, function(a, b)
            local order_a = a.config.order or 1000
            local order_b = b.config.order or 1000
            return order_a < order_b
        end)

        -- Add buttons in sorted order
        for _, prompt_data in ipairs(sorted_prompts) do
            local prompt_config = prompt_data.config
            table.insert(default_options, {
                text = prompt_config.text,
                callback = function(self, question)
                    if self.onAskQuestion then
                        self.onAskQuestion(self, prompt_config.user_prompt .. "\n" .. (question or ""))
                    end
                end
            })
        end
    end

    -- Prepare buttons
    local buttons = {
        {
            text = _("Cancel"),
            id = "close",
            callback = function()
                if self.input_dialog then
                    UIManager:close(self.input_dialog)
                    self.input_dialog = nil
                end
            end
        },
        {
            text = _("Ask"),
            is_enter_default = true,
            callback = function()
                local question = self.input_dialog:getInputText()

                UIManager:close(self.input_dialog)
                self.input_dialog = nil

                if self.onAskQuestion then
                    self.onAskQuestion(self, question)
                end
            end
        }
    }

    -- Add custom prompt buttons
    for _, option in ipairs(default_options) do
        table.insert(buttons, {
            text = option.text,
            callback = function()
                local question = self.input_dialog:getInputText()

                UIManager:close(self.input_dialog)
                self.input_dialog = nil

                option.callback(self, question)
            end
        })
    end

    -- Split buttons into rows (3 buttons per row)
    local button_rows = {}
    for i = 1, #buttons, 3 do
        local row = {}
        for j = 0, 2 do
            if buttons[i + j] then
                table.insert(row, buttons[i + j])
            end
        end
        table.insert(button_rows, row)
    end

    -- Create input dialog
    self.input_dialog = InputDialog:new {
        title = _("Ask Another Question"),
        input = "",
        input_hint = _("Type your question here"),
        input_type = "text",
        width = Screen:getWidth() * 0.8,
        height = Screen:getHeight() * 0.4,
        buttons = button_rows,
        close_callback = function()
            if self.input_dialog then
                UIManager:close(self.input_dialog)
                self.input_dialog = nil
            end
        end
    }

    -- Show the dialog
    UIManager:show(self.input_dialog)
end

function ChatGPTViewer:onShow()
    UIManager:setDirty(self, function()
        return "partial", self.frame.dimen
    end)
    return true
end

function ChatGPTViewer:onTapClose(arg, ges_ev)
    if self.button_table then
        for _, button_row in ipairs(self.button_table.buttons) do
            for _, button in ipairs(button_row) do
                if button.id == "close" and button.dimen then
                    if ges_ev.pos:intersectWith(button.dimen) then
                        self:onClose()
                        return true
                    end
                end
            end
        end
    end

    if ges_ev.pos:notIntersectWith(self.frame.dimen) then
        self:onClose()
        return true
    end

    return false
end

function ChatGPTViewer:onClose()
    local ok, active_window = pcall(function() return UIManager:getActiveWindow() end)

    pcall(function() UIManager:close(self) end)

    pcall(function()
        UIManager:setDirty(nil, "full")
        UIManager:forceRePaint()
    end)

    if self.close_callback then
        pcall(function() self.close_callback() end)
    end

    return true
end

function ChatGPTViewer:onMultiSwipe(arg, ges_ev)
    -- For consistency with other fullscreen widgets where swipe south can't be
    -- used to close and where we then allow any multiswipe to close, allow any
    -- multiswipe to close this widget too.
    self:onClose()
    return true
end

function ChatGPTViewer:onSwipe(arg, ges)
    if ges.pos:intersectWith(self.textw.dimen) then
        local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
        if direction == "west" then
            self.scroll_text_w:scrollText(1)
            return true
        elseif direction == "east" then
            self.scroll_text_w:scrollText(-1)
            return true
        else
            -- trigger a full-screen HQ flashing refresh
            UIManager:setDirty(nil, "full")
            -- a long diagonal swipe may also be used for taking a screenshot,
            -- so let it propagate
            return false
        end
    end
    -- Let our MovableContainer handle swipe outside of text
    return self.movable:onMovableSwipe(arg, ges)
end

-- The following handlers are similar to the ones in DictQuickLookup:
-- we just forward to our MoveableContainer the events that our
-- TextBoxWidget has not handled with text selection.
function ChatGPTViewer:onHoldStartText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHold(_, ges)
end

function ChatGPTViewer:onHoldPanText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    -- We only forward it if we did forward the Touch
    if self.movable._touch_pre_pan_was_inside then
        return self.movable:onMovableHoldPan(arg, ges)
    end
end

function ChatGPTViewer:onHoldReleaseText(_, ges)
    -- Forward Hold events not processed by TextBoxWidget event handler
    -- to our MovableContainer
    return self.movable:onMovableHoldRelease(_, ges)
end

-- These 3 event processors are just used to forward these events
-- to our MovableContainer, under certain conditions, to avoid
-- unwanted moves of the window while we are selecting text in
-- the definition widget.
function ChatGPTViewer:onForwardingTouch(arg, ges)
    -- This Touch may be used as the Hold we don't get (for example,
    -- when we start our Hold on the bottom buttons)
    if not ges.pos:intersectWith(self.textw.dimen) then
        return self.movable:onMovableTouch(arg, ges)
    else
        -- Ensure this is unset, so we can use it to not forward HoldPan
        self.movable._touch_pre_pan_was_inside = false
    end
end

function ChatGPTViewer:onForwardingPan(arg, ges)
    -- We only forward it if we did forward the Touch or are currently moving
    if self.movable._touch_pre_pan_was_inside or self.movable._moving then
        return self.movable:onMovablePan(arg, ges)
    end
end

function ChatGPTViewer:onForwardingPanRelease(arg, ges)
    -- We can forward onMovablePanRelease() does enough checks
    return self.movable:onMovablePanRelease(arg, ges)
end

function ChatGPTViewer:handleTextSelection(text, hold_duration, start_idx, end_idx, to_source_index_func)
    if self.text_selection_callback then
        self.text_selection_callback(text, hold_duration, start_idx, end_idx, to_source_index_func)
        return
    end
    if Device:hasClipboard() then
        -- translator.copyToClipboard(text)
        UIManager:show(Notification:new {
            text = start_idx == end_idx and _("Word copied to clipboard.")
                or _("Selection copied to clipboard."),
        })
    end
end

function ChatGPTViewer:update(new_text)
    -- Attempt to load configuration
    local success, CONFIGURATION = pcall(function() return require("configuration") end)

    -- Check if the new text is substantially different from the current text
    if not self.text or #new_text > #self.text then
        -- Update the text
        self.text = new_text

        -- Create a new ScrollTextWidget with the updated text
        self.scroll_text_w = ScrollTextWidget:new {
            text = new_text,
            face = self.text_face,
            fgcolor = self.fgcolor,
            width = self.width - 2 * self.text_padding - 2 * self.text_margin,
            height = self.textw:getSize().h - 2 * self.text_padding - 2 * self.text_margin,
            dialog = self,
            alignment = self.alignment,
            justified = self.justified,
            lang = self.lang,
            para_direction_rtl = self.para_direction_rtl,
            auto_para_direction = self.auto_para_direction,
            alignment_strict = self.alignment_strict,
        }

        -- Update the frame container with the new scroll widget
        self.textw:clear()
        self.textw[1] = self.scroll_text_w

        -- Always scroll to the new text
        self.scroll_text_w:scrollToBottom()

        -- Refresh the screen after displaying the results
        if success and CONFIGURATION and CONFIGURATION.features and CONFIGURATION.features.refresh_screen_after_displaying_results then
            UIManager:setDirty(nil, "full")
        end
    end
end

return ChatGPTViewer
