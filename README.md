# AITH - AI Tutor for Homework 🎓

AIを活用した家庭教師アプリ。写真を撮るだけで問題を解説、チャットで質問、学習計画作成まで。

![Status](https://img.shields.io/badge/status-in%20development-yellow)
![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android%20%7C%20Web-blue)

## ✨ Features

### 📸 Camera Analysis
- 宿題や問題を撮影するだけでAIが解説
- LaTeX数式対応のリッチなレンダリング
- SVG図形による視覚的説明

### 💬 AI Chat
- 3つのペルソナ（優しい/熱血/厳格）
- 学年レベルに合わせた解説（中高生/大学生/社会人）
- 会話履歴からの学習

### 📚 Learning Tools
| Feature | Description |
|---------|-------------|
| 🎴 単語帳 | 暗記カード機能 |
| 📝 記述添削 | 作文・小論文の添削 |
| 🎤 AI面接 | 面接練習シミュレーター |
| 🗣️ 英会話 | AIとの英会話練習 |
| 📖 AI教材生成 | トピックから教科書・ドリルを自動生成 |

### 📊 Analytics & Gamification
- 学習時間トラッキング
- XP・レベルシステム
- 進捗分析ダッシュボード

## 🚀 Quick Start

### Backend (FastAPI)

```bash
cd backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Create .env file in project root
echo "GEMINI_API_KEY=your_api_key_here" > ../.env

# Run server
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### Flutter App

```bash
cd app

# Get dependencies
flutter pub get

# Update backend URL in lib/constants.dart

# Run app
flutter run
```

## 🔑 Required Credentials

1. **Gemini API Key** - [Google AI Studio](https://aistudio.google.com/apikey)で取得
2. **Firebase** - Firestore用の認証ファイル（`.gitignore`で除外済み）

## 🏗️ Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Flutter (Dart) |
| **Backend** | FastAPI (Python) |
| **AI** | Google Gemini API |
| **Database** | Firebase Firestore |
| **Math Rendering** | flutter_math_fork |

## 📁 Project Structure

```
AITH/
├── app/                    # Flutter Application
│   ├── lib/
│   │   ├── main.dart       # Main app with all screens
│   │   ├── constants.dart  # Backend URL, navigation constants
│   │   ├── screens/        # Extracted screen modules
│   │   ├── widgets/        # Reusable widgets
│   │   └── utils/          # LaTeX processing utilities
│   └── pubspec.yaml
├── backend/                # FastAPI Backend
│   ├── main.py             # API endpoints
│   ├── requirements.txt
│   └── Dockerfile
└── .env                    # API keys (gitignored)
```

## 🔒 Security Notes

- `.env` and Firebase credentials are **gitignored**
- Never commit API keys to the repository
- CORS is configured for development (restrict in production)

## 🔗 Related Projects

Part of the [Enludus](https://enludus.vercel.app/) ecosystem.

## 📄 License

MIT
