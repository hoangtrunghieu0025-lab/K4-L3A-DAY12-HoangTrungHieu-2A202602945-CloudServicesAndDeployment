# ═══════════════════════════════════════════════════════════════════
# CP2 — Production Dockerfile (multi-stage)
#
# Stage 1 `builder`: cài dependency vào /install (được phép nặng, bị vứt đi)
# Stage 2 `runtime`: chỉ copy kết quả + source code, chạy bằng user thường
#
# Build:  docker build -t day12-agent:prod .
# ═══════════════════════════════════════════════════════════════════

# ── Stage 1: builder ───────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /build

# Chỉ copy requirements trước → layer pip install được cache,
# sửa code không phải cài lại thư viện
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime ───────────────────────────────────────────────
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=8000

WORKDIR /app

# Thư viện đã cài từ builder, không mang theo pip cache hay compiler
COPY --from=builder /install /usr/local

# User thường, không có quyền root
RUN useradd --create-home --uid 10001 appuser

# Source code copy SAU cùng (thay đổi thường xuyên nhất)
COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser utils ./utils

USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import os, urllib.request; urllib.request.urlopen(f'http://127.0.0.1:{os.environ.get(\"PORT\", \"8000\")}/health', timeout=4).read()" || exit 1

# sh -c để shell thay ${PORT} — cloud tự gán cổng qua biến PORT.
# exec để uvicorn là PID 1 và nhận thẳng SIGTERM (graceful shutdown ở CP4).
CMD ["sh", "-c", "exec uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
