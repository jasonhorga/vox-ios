# Privacy Policy for Vox Input

**Last Updated:** 2026-03-03

## Overview

Vox Input is a voice-to-text input application for iOS that operates on a **Bring Your Own Key (BYOK)** model. Vox Input does **not** collect, store, or transmit any user data to our servers. We do not operate any backend services.

## Data Collection

**Vox Input collects no user data.** Specifically:

- We do **not** collect personal information
- We do **not** collect usage analytics or telemetry
- We do **not** collect crash reports
- We do **not** use any third-party tracking or advertising SDKs
- We do **not** maintain any user accounts or databases

## Microphone Usage

Vox Input requires microphone access to record your voice for speech-to-text conversion. Audio data is:

1. Recorded locally on your device
2. Sent **directly** from your device to the ASR (Automatic Speech Recognition) API endpoint **you have configured** using **your own API key**
3. Deleted from your device immediately after the transcription is complete

Vox Input never intercepts, stores, copies, or relays your audio data. The audio travels directly from your device to your chosen API provider.

## API Keys

Vox Input uses a BYOK (Bring Your Own Key) model:

- You provide your own API keys for third-party services (e.g., OpenAI Whisper, Alibaba Qwen ASR)
- API keys are stored securely in the iOS Keychain on your device
- API keys are **never** transmitted to us or any third party
- You maintain full control over your API keys and can revoke them at any time through your API provider's dashboard

## Data Flow

The complete data flow in Vox Input is:

```
Your Voice → Your Device (Microphone) → Your Device (Temporary Audio File)
    → Your ASR API Account (Direct HTTPS Request) → Your Device (Text Result)
    → Your Clipboard / Text Field
```

At no point does data pass through any server operated by Vox Input.

## Keyboard Extension

Vox Input includes a keyboard extension that provides voice input across all apps. The keyboard extension:

- Requires "Allow Full Access" to access the microphone and network
- Uses the same BYOK model as the main app
- Does **not** log or transmit keystrokes
- Does **not** collect any text you type or dictate
- Shares configuration with the main app via a secure App Group container

## Offline Mode

When network connectivity is unavailable, Vox Input can fall back to Apple's on-device speech recognition (Speech.framework). In this mode:

- All processing happens entirely on your device
- No data is transmitted over the network
- Apple's standard on-device privacy practices apply

## Local History

Vox Input stores a local history of your transcription results on your device for your convenience:

- History is stored in the app's local storage (App Group UserDefaults)
- History never leaves your device
- You can delete individual records or clear all history at any time from within the app

## Third-Party Services

Vox Input connects to third-party ASR services **only when you configure it to do so** by providing your own API key. The privacy practices of these third-party services are governed by their respective privacy policies:

- **OpenAI (Whisper API):** https://openai.com/privacy
- **Alibaba Cloud (DashScope / Qwen ASR):** https://www.alibabacloud.com/help/en/legal/latest/Chinese-Mainland-Chinese-Mainland-Chinese-Mainland-Chinese-Mainland-Chinese-Mainland-Chinese-Mainland-Chinese-Mainland-Chinese-Mainland-Chinese-Mainland
- **Apple Speech Recognition:** https://www.apple.com/privacy

## Children's Privacy

Vox Input does not knowingly collect any information from children under the age of 13.

## Changes to This Policy

We may update this privacy policy from time to time. Any changes will be reflected in the "Last Updated" date at the top of this document.

## Contact

If you have questions or concerns about this privacy policy, please open an issue on our GitHub repository or contact us at:

- GitHub: https://github.com/jasonhorga/vox-ios

---

**Summary:** Vox Input is a privacy-first, BYOK voice input tool. We have no servers, no databases, no analytics, and no way to access your data. Your voice, your keys, your data.
