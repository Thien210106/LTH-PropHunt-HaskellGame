# Prop Hunt Haskell

Prop Hunt là game đối kháng nhiều người chơi viết bằng Haskell. Hider hóa thân thành các vật thể trên bản đồ và sống sót hết thời gian; Hunter tìm, nhìn thấy và bắt Hider bằng dao.

Mã nguồn hiện có hai phần:

- [`PropHuntv2.hs`](./PropHuntv2.hs): game engine thuần trạng thái, xử lý luật chơi, bản đồ, bot, tầm nhìn và trạng thái theo tick.
- [`PropHuntServer.hs`](./PropHuntServer.hs): WebSocket server authoritative. Client chỉ gửi action; server gửi lại phần state mà từng người chơi được phép nhìn thấy.

Tài liệu chi tiết nằm tại [`docs/PROPHUNT.md`](./docs/PROPHUNT.md). Ghi chú triển khai multiplayer hiện có ở [`MULTIPLAYER.md`](./MULTIPLAYER.md).

## Chạy local

Yêu cầu:

- GHC/Cabal tương thích với `base >= 4.14 && < 5`.
- Các package trong [`prophunt-multiplayer.cabal`](./prophunt-multiplayer.cabal): `aeson`, `bytestring`, `containers`, `websockets`.

Build và chạy server:

```powershell
cabal build prophunt-server
cabal exec prophunt-server
```

Server lắng nghe tại `ws://0.0.0.0:9160`. Client trong cùng máy có thể kết nối tới `ws://127.0.0.1:9160`; client trong mạng LAN dùng IP của máy chạy server.

## Luật chơi tóm tắt

- Mỗi trận có 3 Hunter và từ 8 đến 12 Hider.
- Lobby kéo dài 120 giây; người chơi vote một trong ba map.
- Sau khi chọn map, Hider có 20 giây chuẩn bị; Hunter bị khóa.
- Trận đấu kéo dài 8 phút. Mỗi Hider bị bắt cộng thêm 20 giây cho thời gian sống còn.
- Hider có thể `morph`, đổi prop sau cooldown, tạo tối đa hai fake prop và `revert`.
- Hunter di chuyển nhanh hơn và dùng `attack`; dao có cooldown 8 tick.
- Hider thắng nếu còn sống đến hết thời gian. Hunter thắng nếu bắt hết Hider.

## Giao thức action

Client gửi text JSON qua WebSocket:

```json
{"action":"move","dx":1,"dy":0}
{"action":"morph"}
{"action":"swapMorph"}
{"action":"duplicate"}
{"action":"revert"}
{"action":"attack"}
{"action":"vote","map":0}
```

Server trả về message `state`, gồm phase, tick, thời gian, thông báo, danh sách player nhìn thấy và fake prop nhìn thấy. Hider nằm ngoài tầm nhìn bị loại khỏi payload, không chỉ bị ẩn ở giao diện.

## Trạng thái hiện tại

Workspace này có engine và server mẫu, nhưng chưa có frontend/browser client. Vì vậy cần một client WebSocket riêng để hiển thị map, điều khiển nhân vật và diễn giải các message `state`.
