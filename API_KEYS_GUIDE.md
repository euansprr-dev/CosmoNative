# API Keys Configuration Guide

## Overview

CosmoOS now stores API keys securely in the **macOS Keychain** instead of environment variables. This means:

✅ **For You (Developer)**: Your API keys are stored securely and persist across app launches
✅ **For Users**: They can enter their own API keys directly in the app's Settings
✅ **For Distribution**: When you publish the app, users will add their own keys - you don't need to share yours!

## How to Add Your API Keys

### Option 1: Using the App's Settings (Recommended)

1. **Launch the app**:
   ```bash
   cd /Users/euanspencer/Cosmo-Local-BCKP/CosmoOS
   open CosmoOS.app
   ```

2. **Open Settings**:
   - Press `⌘,` (Command + Comma)
   - Or use the settings button in the app

3. **Navigate to "API Keys" tab**

4. **Enter your API keys**:
   - **OpenRouter API Key** (Required): Enter your `sk-or-v1-...` key
   - **YouTube API Key** (Optional): Enter your `AIza...` key
   - **Perplexity API Key** (Optional): Enter your `pplx-...` key

5. **Click the arrow button** next to each key to save

6. **Verify**: You'll see a green checkmark when the key is saved successfully

### Option 2: Migrate from Environment Variable

If you already have the API key in your `~/.zshrc` file, it will still work! The app checks both:
1. **First**: Keychain (new method)
2. **Fallback**: Environment variables (backward compatible)

To migrate to the new system:
1. Open the app and go to Settings → API Keys
2. Copy your key from `~/.zshrc`
3. Paste it into the app
4. Click save
5. (Optional) Remove the old entries from `~/.zshrc`

## Where to Get API Keys

### OpenRouter (Required for AI Features)
1. Visit https://openrouter.ai
2. Sign up or log in
3. Navigate to the "Keys" section
4. Create a new API key
5. Copy the key starting with `sk-or-v1-...`

### YouTube Data API (Optional)
1. Visit https://console.cloud.google.com
2. Create a new project
3. Enable "YouTube Data API v3"
4. Go to "Credentials" and create an API Key
5. Copy the key starting with `AIza...`

### Perplexity (Optional)
1. Visit https://www.perplexity.ai
2. Sign up or log in
3. Go to API settings
4. Generate a new API key
5. Copy the key starting with `pplx-...`

## For Publishing Your App

When you distribute your app:

1. **Do NOT include your API keys** in the app bundle
2. **Users will need to provide their own keys** through Settings
3. Consider adding a "Getting Started" guide that explains:
   - Which API keys are required
   - Where to get them
   - How to add them in Settings

## Security Features

- ✅ **Keychain Storage**: Keys are encrypted by macOS Keychain
- ✅ **No Plain Text**: Keys are never stored in plain text files
- ✅ **App Sandbox**: Keys are only accessible to your app
- ✅ **Secure Input**: Password fields hide keys while typing
- ✅ **Visual Confirmation**: Green checkmark shows when keys are saved

## Troubleshooting

### "API key not found" error
- Open Settings (⌘,)
- Go to API Keys tab
- Verify the OpenRouter key is entered and saved (green checkmark visible)
- Try removing and re-entering the key

### Keys not persisting
- Make sure you clicked the arrow button to save
- Check that the app has Keychain access (should be automatic)
- Try relaunching the app

### Still using environment variables?
- The old method still works as a fallback
- But the new Keychain method is more secure and user-friendly
- Migrate to the new system for the best experience

## Current Status

To check which keys are configured, the app prints a status message on launch:

```
🔑 API Key Status:
   OpenRouter: ✅ Configured
   YouTube: ⚪ Optional (configure in Settings)
   Perplexity: ⚪ Optional (configure in Settings)
```

## Questions?

If you have any issues:
1. Check the console logs when launching the app
2. Verify the Settings → API Keys panel shows your keys as saved
3. Make sure you're using a valid API key format
