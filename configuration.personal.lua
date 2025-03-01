local CONFIGURATION = {
    -- Choose your preferred AI provider: "anthropic", "openai", "gemini", "openrouter" or "deepseek"
    provider = "gemini",

    -- Provider-specific settings
    provider_settings = {
        gemini = {
            model = "gemini-2.0-flash", -- model list: https://ai.google.dev/gemini-api/docs/models/gemini , ex: gemini-1.5-pro-latest , gemini-2.0-flash-001
            base_url = "https://generativelanguage.googleapis.com/v1beta/models/",
            api_key = "PLACE_API_KEY_HERE",
            additional_parameters = {
                temperature = 1,
                max_tokens = 8000
            }
        },
    },

    -- Optional features, replace each "Persian" with your desired language
    features = {
        hide_highlighted_text = false,                                                   -- Set to true to hide the highlighted text at the top
        hide_long_highlights = true,                                                     -- Hide highlighted text if longer than threshold
        long_highlight_threshold = 500,                                                  -- Number of characters considered "long"
        system_prompt = "You are a helpful assistant that provides clear explanations.", -- Custom system prompt for the AI ("Ask" button) to override the default, to disable set to nil
        refresh_screen_after_displaying_results = true,                                  -- Set to true to refresh the screen after displaying the results
        show_dictionary_button_in_main_popup = true,                                     -- Set to true to show the dictionary button in the main popup
        dictionary_translate_to = "en-EN",
        show_dictionary_button_in_dictionary_popup = true,                             -- Set to true to show the dictionary button in the dictionary popup

        -- Custom prompts for the AI (text = button text in the UI). system-prompt defaults to "You are a helpful assistant." if not set.
        prompts = {
            trans = {
                text = "Lang-Help",
                order = 1,
                system_prompt =
                "You are a helpful language assistant for Persian text. Provide translations to English and romanizations without additional commentary.",
                user_prompt = "Please romanize and translate the following text to English: ",
                show_on_main_popup = true -- Show the button in main popup
            },
            translate = {
                text = "AI-Translate",
                order = 2,
                system_prompt =
                "You are a helpful translation assistant. Provide direct translations without additional commentary.",
                user_prompt = "Please romanize and translate the following text to English: ",
                show_on_main_popup = true -- Show the button in main popup
            },
            simplify = {
                text = "Romanize",
                order = 3,
                system_prompt =
                "You are a helpful language assistant. Romanize any text given without additional commentary.",
                user_prompt = "Please romanize the following Persian Text: ",
                show_on_main_popup = true -- Show the button in main popup
            },
            explain = {
                text = "Explain",
                order = 4,
                system_prompt =
                "You are a helpful assistant that explains complex topics clearly and concisely. Break down concepts into simple terms.",
                user_prompt = "Please explain the following text. Answer in English: ",
                show_on_main_popup = false -- Show the button in main popup
            },
            grammar = {
                text = "Grammar",
                order = 5,
                system_prompt = "You are a grammar expert.",
                user_prompt = "Explain the grammar of the following Persian text. Answer in English: ",
                show_on_main_popup = true -- Show the button in main popup
            }
            -- summarize = {
            --     text = "Summarize",
            --     order = 4,
            --     system_prompt =
            --     "You are a summarization expert. Provide clear, concise summaries that capture the main points.",
            --     user_prompt = "Please provide a concise summary of the following text in its own language: ",
            --     show_on_main_popup = false -- Show the button in main popup
            -- },
            -- historical_context = {
            --     text = "Historical Context",
            --     order = 5,
            --     system_prompt =
            --     "You are a historical context expert. Provide relevant historical background and connections.",
            --     user_prompt = "Explain the historical context of this text. Answer in Persian: ",
            --     show_on_main_popup = false -- Show the button in main popup
            -- },
            -- key_points = {
            --     text = "Key Points",
            --     order = 6,
            --     system_prompt = "You are a key points expert. Provide a concise list of key points from the text.",
            --     user_prompt = "Please provide a concise list of key points from the following text. Answer in English: ",
            --     show_on_main_popup = false -- Show the button in main popup
            -- },
            -- ELI5 = {
            --     text = "ELI5",
            --     order = 7,
            --     system_prompt = "You are an ELI5 expert. Provide simple, concise explanations for complex terms.",
            --     user_prompt = "Please provide an ELI5 explanation. Answer in English: ",
            --     show_on_main_popup = false -- Show the button in main popup
            -- },
        }
    }
}

return CONFIGURATION
