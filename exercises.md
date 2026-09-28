# Phiếu Phản Ánh — K4 Level 3A, Ngày 12

> **Bài làm cá nhân.** Trả lời bằng lời của chính bạn, dựa trên những gì bạn
> quan sát được khi chạy code — không sao chép đáp án của người khác.
>
> Cách trả lời: thay dòng `> *Câu trả lời của bạn*` bằng câu trả lời.
> `grade.py` đếm số câu đã trả lời (15 điểm cho 10 câu).
>
> Họ và tên: Hoàng Trung Hiếu  Mã học viên: 2A202602945

---

### Câu 1 — Fail fast (CP1)

Trong `Settings`, `agent_api_key` không có giá trị mặc định nên app chết ngay
khi khởi động nếu thiếu biến môi trường. Hãy mô tả một tình huống cụ thể mà
việc "chết sớm" này cứu bạn, so với việc để mặc định `"changeme"`.

Tình huống em gặp thật khi deploy lên Railway: lần đầu em quên tạo biến
`AGENT_API_KEY` cho service agent. Nếu `Settings` có mặc định `"changeme"`,
app vẫn khởi động, dashboard báo "Online", và `/ask` chấp nhận khóa
`changeme`, một chuỗi ai đọc repo cũng biết. Service công khai trên Internet,
nên bất kỳ ai cũng gọi được LLM và tiêu ngân sách của em; em chỉ phát hiện khi
nhìn hóa đơn.

Không có mặc định thì pydantic ném `ValidationError` ngay khi đọc cấu hình.
Em còn thêm `get_settings()` vào `lifespan` để lỗi xảy ra lúc **khởi động**
chứ không đợi request đầu tiên: deploy thiếu secret sẽ fail health check và
Railway giữ bản cũ, lỗi hiện ra ngay lúc em đang nhìn màn hình.

---

### Câu 2 — Log cho máy đọc (CP1)

Chạy service và gọi `/ask` vài lần. Dán một dòng log JSON bạn thu được, rồi
nêu **hai** việc bạn làm được với dòng log đó mà `print("đã trả lời xong")`
không làm được.

Dòng log thật khi gọi `/ask` qua `docker compose`:

```json
{"event": "ask_completed", "level": "info", "timestamp": "2026-09-28T07:50:20.797993+00:00", "user_id": "hieu", "tokens_in": 48, "tokens_out": 52, "cost_usd": 3.84e-05}
```

Hai việc làm được mà `print("đã trả lời xong")` không làm được:
1. **Lọc và tổng hợp theo trường**: ví dụ lọc `event == "ask_completed"`,
   nhóm theo `user_id` rồi cộng `cost_usd` để biết user nào tiêu nhiều tiền
   nhất hôm nay, hoặc tính số token trung bình mỗi request.
2. **Đặt cảnh báo và đếm theo thời gian**: vì có `timestamp` và `level`, hệ
   thống log (Railway, Datadog...) có thể đếm số dòng `level == "error"` trong
   5 phút gần nhất và cảnh báo khi vượt ngưỡng. Với chuỗi tự do thì phải viết
   regex, dễ vỡ khi ai đó đổi câu chữ.

---

### Câu 3 — Kích thước image (CP2)

Build cả hai phiên bản và ghi lại số đo thật:

```bash
docker build -f <Dockerfile-1-stage> -t agent:single .
docker build -t agent:multi .
docker images | grep agent
```

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu) | ... MB |
| Multi-stage | ... MB |

Giải thích: phần dung lượng chênh lệch đó là những gì?

Số đo thật trên máy em (Docker 29.1, `docker images`):

| Bản | Dung lượng |
|-----|-----------|
| 1 stage (bản đầu, `python:3.11`) | 1.73 GB (~1770 MB) |
| Multi-stage (`python:3.11-slim`) | 271 MB |

Chênh lệch ~1.46 GB chủ yếu gồm:
- **Base image đầy đủ `python:3.11`**: có sẵn gcc, build-essential, header
  của nhiều thư viện C, git, bộ công cụ Debian đầy đủ... để biên dịch được mọi
  thứ. App của em không cần chúng lúc chạy. `slim` chỉ giữ Python và thư viện
  hệ thống tối thiểu.
- **Pip cache và file tạm khi cài**: bản 1 stage chạy `pip install` không có
  `--no-cache-dir` (`docker history` cho thấy layer đó 95 MB). Bản multi-stage
  cài ở stage `builder` rồi chỉ `COPY --from=builder /install`, nên cache và
  công cụ build bị bỏ lại cùng stage đó.
- `COPY . .` ở bản đầu kéo theo mọi thứ trong thư mục; với `.dockerignore`
  ban đầu (chỉ có `.git`) thì `.venv` và cả `.env` cũng nằm trong image.

---

### Câu 4 — Thứ tự lệnh trong Dockerfile (CP2)

Sửa một ký tự trong `app/main.py` rồi build lại. Với Dockerfile của bạn, những
layer nào được dùng lại từ cache, layer nào phải chạy lại? Nếu bạn đặt
`COPY . .` lên trước `RUN pip install` thì kết quả khác thế nào?

Em đổi `SERVICE_VERSION = "1.0.0"` thành `"1.0.1"` rồi build lại với
`--progress=plain`:

- **Dùng lại cache (`CACHED`)**: `FROM python:3.11-slim`, `WORKDIR`,
  `COPY requirements.txt`, `RUN pip install ...`, `COPY --from=builder`,
  `RUN useradd`.
- **Chạy lại**: chỉ `COPY app ./app` và `COPY utils ./utils`. Tổng thời gian
  build dưới 1 giây.

Với Dockerfile ban đầu (`COPY . .` đứng trước `RUN pip install`), em làm đúng
thí nghiệm đó: `COPY . .` thay đổi nên cache bị hủy từ đó trở đi, và
`RUN pip install -r requirements.txt` chạy lại từ đầu, **mất khoảng 300 giây**
trên máy em. Lý do: Docker cache theo từng layer và hủy toàn bộ cache từ layer
đầu tiên có input thay đổi. `requirements.txt` hiếm khi đổi còn code đổi liên
tục, nên phải copy requirements và cài thư viện trước, copy code sau cùng.

---

### Câu 5 — Vì sao không chạy bằng root (CP2)

Container mặc định chạy bằng root. Mô tả chuỗi sự kiện dẫn từ "một lỗ hổng
trong code Python của bạn" tới "kẻ tấn công có quyền cao trên máy host", và
lệnh `USER` cắt đứt chuỗi đó ở chỗ nào.

Chuỗi sự kiện khi container chạy bằng root:
1. Code Python có lỗ hổng (ví dụ deserialize dữ liệu không tin cậy, hoặc một
   thư viện dính lỗi RCE) → kẻ tấn công chạy được lệnh trong container.
2. Process đang là **root (UID 0)** → họ có toàn quyền trong container: cài
   công cụ, đọc mọi file, sửa code của app.
3. UID 0 trong container cũng là UID 0 trên kernel của host (khi không dùng
   user namespace). Chỉ cần thêm một lỗi cấu hình (mount
   `/var/run/docker.sock`, mount thư mục host, `--privileged`) hoặc một lỗ hổng
   escape của kernel/runtime là họ thành root trên máy host, kéo theo mọi
   container khác.

`USER appuser` (UID 10001) cắt chuỗi ở **bước 2**: lệnh của kẻ tấn công chạy
với quyền user thường, không ghi được vào thư mục hệ thống, không cài được gói,
không đọc được file của root. Nếu có thoát ra host thì cũng chỉ là một UID
không có quyền. Em đã kiểm tra: `docker run --entrypoint whoami` in ra
`appuser`.

---

### Câu 6 — Cửa sổ trượt (CP3)

Rate limit của bạn dùng sliding window 60 giây. Nếu thay bằng cách đếm theo
phút đồng hồ (reset lúc giây 00), một người dùng có thể gửi tối đa bao nhiêu
request trong 2 giây liên tiếp khi hạn mức là 10/phút? Giải thích cách đạt được
con số đó.

Tối đa **20 request trong khoảng 2 giây**.

Cách làm: đếm theo phút đồng hồ nghĩa là bộ đếm reset ở giây :00. Người dùng
gửi 10 request lúc 10:00:59 (hết quota của phút 10:00), rồi gửi thêm 10
request lúc 10:01:00–10:01:01 (quota của phút mới vừa reset). Cả 20 request
đều "đúng luật" dù nằm gọn trong 2 giây, tức gấp đôi hạn mức thực tế.

Sliding window đếm số request trong **60 giây gần nhất tính từ bây giờ**
(ZSET, score = timestamp, xóa entry cũ hơn `now - 60`). Lúc 10:01:00, 10
request lúc 10:00:59 vẫn nằm trong cửa sổ nên request thứ 11 bị 429. Em đã
kiểm tra trên Railway: 15 request liên tiếp cho ra `200` ×10 rồi `429` ×5.

---

### Câu 7 — Rate limit và cost guard (CP3)

Hai cơ chế này khác nhau ở điểm nào? Cho một tình huống mà rate limit cho qua
nhưng cost guard phải chặn, và một tình huống ngược lại.

- **Rate limit** giới hạn **số lượng request theo thời gian** (10/phút),
  chống spam và bảo vệ tài nguyên server.
- **Cost guard** giới hạn **tổng tiền theo tháng** ($10/user), bảo vệ hóa đơn
  LLM. Nó tính trên chi phí thật (`cost_usd` = token × giá), nên phụ thuộc độ
  dài prompt chứ không phụ thuộc số lần gọi.

Rate limit cho qua nhưng cost guard chặn: một user gửi đều 5 request/phút
(dưới hạn mức), nhưng mỗi request là một tài liệu dài hàng chục nghìn token và
lịch sử cũng dài. Sau vài ngày, tổng chi phí vượt $10 → 402, dù chưa bao giờ
chạm rate limit.

Cost guard cho qua nhưng rate limit chặn: một script gửi 15 câu ngắn `"test"`
trong vài giây. Mỗi câu chỉ tốn ~0.00003 USD nên ngân sách gần như còn nguyên,
nhưng từ request thứ 11 là bị 429 (đúng như em đo được trên Railway).

---

### Câu 8 — /health khác /ready (CP4)

Nếu gộp hai endpoint làm một và cho nó kiểm tra Redis, chuyện gì xảy ra với cụm
3 container khi Redis mất kết nối 30 giây? Trả lời theo đúng thứ tự sự kiện.

Nếu `/health` cũng kiểm tra Redis, khi Redis mất kết nối 30 giây:

1. Giây 0: Redis mất kết nối. Cả 3 container cùng trả 503 ở endpoint gộp.
2. Load balancer ngừng gửi traffic vào cả 3 → toàn bộ service ngừng phục vụ.
3. Nhưng orchestrator cũng dùng endpoint đó làm **liveness probe**. Sau vài
   lần fail liên tiếp (ví dụ 3 lần × 10 giây), nó kết luận process bị treo và
   **restart cả 3 container**, dù Python vẫn chạy bình thường.
4. Request đang xử lý dở bị cắt. Container khởi động lại cần thêm thời gian,
   và liveness vẫn fail nếu Redis chưa về → vòng lặp restart (CrashLoop).
5. Giây 30: Redis trở lại, nhưng các container đang restart dở nên service
   còn ngừng thêm một lúc. Sự cố 30 giây của Redis thành sự cố dài hơn của cả
   cụm.

Khi tách riêng: `/health` (liveness) không chạm Redis nên vẫn 200 và không có
restart nào. `/ready` trả 503 nên load balancer tạm ngừng gửi traffic. Redis
về thì `/ready` lại 200 và traffic quay lại ngay, không mất container nào.

---

### Câu 9 — Stateless (CP4)

Chạy `docker compose up --scale agent=3` rồi gọi `/ask` nhiều lần với cùng một
`X-User-Id`. Quan sát `history_length` trong response. Nếu lịch sử được lưu
trong một dict Python thay vì Redis, bạn sẽ thấy con số đó thay đổi thế nào?

Em chạy 3 container agent (`docker compose ... --scale agent=3`) dùng chung
một Redis, rồi gửi 6 request `/ask` cùng `X-User-Id: scale-demo`, lần lượt vào
từng container:

```
request 1 -> container 148832120a05 history_length = 0
request 2 -> container b76c942fc6bb history_length = 2
request 3 -> container 515b21c5acd4 history_length = 4
request 4 -> container 148832120a05 history_length = 6
request 5 -> container b76c942fc6bb history_length = 8
request 6 -> container 515b21c5acd4 history_length = 10
```

`history_length` tăng đều 2 mỗi lượt (1 message user + 1 message assistant)
dù mỗi request rơi vào một container khác nhau, vì lịch sử nằm trong Redis.

Nếu lưu trong dict Python, mỗi container có một dict riêng trong RAM. Kết quả
sẽ là `0, 0, 0, 2, 2, 2`: mỗi container chỉ thấy các lượt đã đi qua chính nó,
agent "mất trí nhớ" mỗi khi load balancer đổi instance, và mất sạch khi
container restart. Em cũng đã thử restart container agent: lịch sử vẫn còn
(`history_length` từ 2 lên 4), điều mà dict trong RAM không làm được.

---

### Câu 10 — Deploy thật (CP5)

Ghi lại **một** lỗi bạn gặp khi deploy lên cloud (build fail, health check
timeout, sai REDIS_URL, app không đọc `$PORT`...): thông báo lỗi là gì, bạn
tìm ra nguyên nhân bằng cách nào, và sửa ra sao?

**Lỗi:** sau khi deploy lên Railway, dashboard báo cả `day12-agent` và
`day12-redis` đều Online, `/health` trả 200, nhưng `/ready`, `/ask` không có
key và `/ask` có key **đều trả 500**.

**Cách tìm nguyên nhân:**
1. Nhìn vào mẫu lỗi: `/health` là endpoint duy nhất không đọc cấu hình, và cũng
   là endpoint duy nhất chạy được. `/ask` không có key đáng lẽ phải trả 401,
   nhưng bước kiểm tra key cũng gọi `get_settings()`. Vậy lỗi nằm ở việc đọc
   cấu hình.
2. Mở tab Variables của service agent: **thiếu hẳn `AGENT_API_KEY`**, và
   `REDIS_URL` hiện `<empty string>`, vì em tham chiếu `${{Redis.REDIS_URL}}`
   trong khi service Redis tên là `day12-redis`.

**Cách sửa:**
- Đặt `REDIS_URL = ${{day12-redis.REDIS_URL}}` (Railway tự thay bằng địa chỉ
  nội bộ `day12-redis.railway.internal`) và thêm `AGENT_API_KEY`. Sau khi
  redeploy, `/ready` trả `{"status":"ready","redis":true}` và toàn bộ test CP5
  pass.
- Rút kinh nghiệm: app thiếu secret mà vẫn "Online" nghĩa là chưa fail fast
  thật sự. Em thêm `get_settings()` vào `lifespan` để lần sau thiếu biến thì
  deploy fail ngay và Railway giữ bản cũ, thay vì chạy rồi trả 500.
