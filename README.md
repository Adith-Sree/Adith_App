# 🧠 Autonomous Deep Work Broker

A high-precision, cyberpunk-styled productivity supervisor built to enforce focus intervals. It tracks commitments, computes discipline metrics, and employs an AI agent to aggressively push back when you try to break focus.

---

## 🏗️ Architecture Overview

The system is split into two decoupled components:

1. **Backend Service (`/backend`)**: A containerized FastAPI application using SQLModel (SQLAlchemy) and PostgreSQL. It orchestrates the database, computes historical analytics, and streams AI pushbacks powered by **Google Gemini** models via `smolagents` & `litellm`.
2. **Frontend Client (`/frontend`)**: A multi-platform Flutter application built with custom visual metrics, real-time logging terminal, checklist synchronization, and active state management.

---

## 🛠️ Tech Stack & Key Files

### Backend
- **Framework:** FastAPI
- **Database ORM:** SQLModel (SQLAlchemy)
- **Database Engine:** PostgreSQL (production) / SQLite (local fallback)
- **AI Agent Integration:** `smolagents` + `litellm`
- **Key Files:**
  - [main.py](file:///Users/adithsreepuram/deep-work-broker/backend/app/main.py): Service entrypoint, CORS configuration, and route registrations.
  - [session.py](file:///Users/adithsreepuram/deep-work-broker/backend/app/db/session.py): Production-grade database connection pool.
  - [security.py](file:///Users/adithsreepuram/deep-work-broker/backend/app/core/security.py): API authorization middleware.

### Frontend
- **Framework:** Flutter (Channel Stable)
- **Language:** Dart
- **Key Files:**
  - [main.dart](file:///Users/adithsreepuram/deep-work-broker/frontend/lib/main.dart): Client entrypoint.
  - [dashboard_screen.dart](file:///Users/adithsreepuram/deep-work-broker/frontend/lib/screens/dashboard_screen.dart): State-driven focus center, timers, terminal logger, and custom canvas charts.
  - [api_service.dart](file:///Users/adithsreepuram/deep-work-broker/frontend/lib/services/api_service.dart): Compile-time configurable HTTP interface.

---

## 🚀 Local Development Setup

### 1. Backend Setup
Navigate to `/backend`:
```bash
cd backend
```

Create a virtual environment and install dependencies:
```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

Create a local `.env` file in the `backend/` directory:
```env
DATABASE_URL=sqlite:///./local.db
GEMINI_API_KEY=your_gemini_api_key
APP_API_KEY=your_optional_dev_auth_token
```

Start the local server:
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

---

### 2. Frontend Setup
Navigate to `/frontend`:
```bash
cd frontend
```

Make sure dependencies are retrieved:
```bash
flutter pub get
```

#### Run/Build Configurations:
Pass configurations securely at compile-time using `--dart-define`:

- **Run on local macOS Desktop (pointing to local backend):**
  ```bash
  flutter run -d macos --dart-define=API_BASE_URL=http://127.0.0.1:8000/api
  ```
- **Run on physical Android Device/Emulator:**
  ```bash
  flutter run -d <device-id> --dart-define=API_BASE_URL=http://10.0.2.2:8000/api
  ```
- **Build Release APK (pointing to your DigitalOcean deployment):**
  ```bash
  flutter build apk --dart-define=API_BASE_URL=https://shark-app-dsh7f.ondigitalocean.app/api
  ```

---

## 🌐 Production Deployment

### 1. DigitalOcean App Platform (Recommended)
This repository includes a deployment spec: [app.yaml](file:///Users/adithsreepuram/deep-work-broker/app.yaml).
- Connect your GitHub fork to DigitalOcean.
- DigitalOcean detects the `app.yaml` automatically.
- Paste your `GEMINI_API_KEY` into the secrets prompt and launch!

### 2. Render Blueprint
This repository also contains a Render configuration: [render.yaml](file:///Users/adithsreepuram/deep-work-broker/render.yaml), supporting quick deployment of a Python Web Service and managed PostgreSQL instance.
