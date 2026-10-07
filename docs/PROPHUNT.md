# Tài liệu Prop Hunt

## 1. Mục đích

`PropHuntv2` là simulation engine deterministic theo tick cho một trận Prop Hunt. Engine không thực hiện I/O, không biết WebSocket và không render giao diện. Nó nhận `Game` cùng `PlayerAction`, rồi tạo ra `Game` mới.

Server dùng engine theo mô hình authoritative:

```text
Client -- action JSON --> PropHuntServer --> applyAction --> Game
                                      \\
                                       stepGame mỗi 130 ms
                                        |
                         visiblePlayers / visibleFakes
                                        |
                              state JSON theo từng client
```

## 2. Thành phần dữ liệu

### Map và vị trí

`Pos` là tọa độ `(x, y)`. Mỗi `World` gồm:

- `wWalls`: ô không đi qua được;
- `wProps`: map từ vị trí sang loại prop thật;
- `wBushes`: ô bụi cây, ảnh hưởng đến visibility;
- `wFloors`: các ô đi được;
- `wPlayer`, `wSeeker`: vị trí spawn gốc của Hider và Hunter;
- `wSize`, `wName`: kích thước và tên map.

Map được khai báo dạng ASCII trong `maps`. Ký tự được chuyển thành `World` bởi `mkWorld`; `worlds` là danh sách map đã parse.

### Player và Game

`Player` lưu role, quyền điều khiển (`Human`/`Bot`), vị trí, prop đang hóa thân, cooldown, số fake prop và trạng thái sống.

`Game` là state đầy đủ của trận: map, phase, player list, vote, RNG seed, đồng hồ, fake props, giới hạn thời gian và hunter streak.

Các phase:

| Phase | Ý nghĩa |
|---|---|
| `Lobby` | Chờ người chơi, vote map; role chỉ là placeholder. |
| `HiderPrepare` | Hider được di chuyển và chuẩn bị; Hunter bị khóa trong 20 giây. |
| `Playing` | Cả hai role hoạt động; bot được cập nhật mỗi tick. |
| `GameOver` | Trận kết thúc, không nhận action gameplay. |

## 3. Vòng đời trận

1. `startLobby seed humanIds` tạo lobby, bổ sung bot cho đủ đội hình và chọn ba map ứng viên.
2. Người chơi tham gia bằng `addHumanPlayer`; người mới thay thế một bot trong lobby.
3. `castVote` lưu một vote/người. Vote lại sẽ thay vote cũ.
4. Khi lobby hết 120 giây, `chooseMap` chọn map có nhiều vote nhất; nếu hòa thì chọn pseudo-random.
5. `randomizeRoles` chọn đúng ba Hunter có trọng số giảm cho người vừa làm Hunter nhiều lần.
6. `assignSpawns` đặt Hunter gần `wSeeker` và Hider gần `wPlayer`.
7. Hết 20 giây chuẩn bị, phase chuyển sang `Playing`.
8. `stepGame` giảm cooldown, chạy bot, tăng tick, chuyển phase và kiểm tra điều kiện thắng.

Một tick dài 130 ms. Các giá trị thời gian được đổi sang tick bằng phép chia cho `tickMs`.

## 4. Cơ chế gameplay

### Di chuyển

Action `Move (dx, dy)` được giới hạn theo tốc độ:

- Hider: tối đa 1 ô mỗi trục trong một action;
- Hunter: tối đa 2 ô mỗi trục trong một action.

Không thể đi vào tường, ra ngoài map, chiếm ô prop thật hoặc chiếm ô của player còn sống khác.

### Hider

- `Morph`: tìm prop thật gần nhất trong bán kính Chebyshev 2 và chuyển tới đúng vị trí đó.
- `SwapMorph`: đổi sang prop gần nhất khi đã hóa thân; cooldown khoảng 35 giây.
- `Duplicate`: tạo tối đa hai fake prop ở ô trống cạnh player.
- `Revert`: trở lại hình người và xóa fake prop của mình.

Khi Hider bị bắt, player bị đánh dấu `pAlive = False`, bị xóa form/fake props và thời gian trận được cộng 20 giây.

### Hunter

`Attack` chỉ có tác dụng khi Hunter không còn cooldown, Hider còn sống và nằm trong tầm nhìn, đồng thời khoảng cách bình phương không vượt `knifeHitbox²` (hitbox hiện tại là 1.5).

Dao có cooldown 8 tick. Đánh trúng fake prop chỉ tạo thông báo; Hider thật vẫn an toàn.

### Tầm nhìn và bụi cây

Tầm nhìn cơ bản là 6 ô và bị chặn bởi tường. Hider trong bụi cây không bị Hunter ở ngoài bụi phát hiện chính xác. Người đang ở trong bụi thấy mục tiêu gần trong phạm vi 2 ô. Logic này được dùng cho cả player và fake prop.

`visiblePlayers viewerId game` và `visibleFakes viewerId game` là ranh giới bảo mật cho client. Server phải dùng hai hàm này khi serialize state; không gửi trực tiếp toàn bộ `players` cho client.

## 5. API engine công khai

Các hàm chính được export từ [`PropHuntv2.hs`](../PropHuntv2.hs):

| Hàm | Vai trò |
|---|---|
| `startLobby` / `startLobbyWithPlayers` | Tạo lobby và đội hình bot/human. |
| `startGame` | Helper test: bắt đầu trực tiếp trên một map với đội hình đầy đủ bot. |
| `addHumanPlayer` | Thay một bot trong lobby bằng human. |
| `castVote` / `chooseMap` | Vote và chốt map. |
| `applyAction` | Route action theo phase và role. |
| `stepGame` | Một tick authoritative của server. |
| `randomizeRoles` | Random role, giảm hunter streak. |
| `visiblePlayers` / `visibleFakes` | Tạo state view an toàn theo người xem. |
| `visibleTo` / `knifeHits` | Kiểm tra visibility và hitbox. |

Ví dụ khởi tạo và chạy simulation trong GHCi:

```haskell
:load PropHuntv2.hs
let g0 = startGame 0 2026
let g1 = applyAction (PlayerAction (PlayerId 1) (Move (1, 0))) g0
let g2 = stepGame g1
phase g2
```

## 6. WebSocket server

[`PropHuntServer.hs`](../PropHuntServer.hs) giữ `Server` trong `MVar` để serialize cập nhật state giữa các connection. Tick loop chạy mỗi 130 ms và broadcast state riêng cho từng client.

Khi client kết nối, server cấp `PlayerId` lớn hơn ID đang dùng rồi gọi `addHumanPlayer`. Nếu lobby đã đầy hoặc trận đã bắt đầu, người chơi mới không được chèn vào đội hình hiện tại.

### Action JSON

| JSON | Engine action | Điều kiện |
|---|---|---|
| `{"action":"move","dx":1,"dy":0}` | `Move (1, 0)` | Hider/Hunter còn sống. |
| `{"action":"morph"}` | `Morph` | Chỉ Hider, chưa hóa thân. |
| `{"action":"swapMorph"}` | `SwapMorph` | Chỉ Hider đã hóa thân, hết cooldown. |
| `{"action":"duplicate"}` | `Duplicate` | Chỉ Hider đã hóa thân, tối đa 2 fake. |
| `{"action":"revert"}` | `Revert` | Chỉ Hider. |
| `{"action":"attack"}` | `Attack` | Chỉ Hunter, hết cooldown. |
| `{"action":"vote","map":0}` | `Vote 0` | Chỉ trong lobby và map hợp lệ. |

Message state có dạng khái quát:

```json
{
  "type": "state",
  "playerId": 1,
  "phase": "Playing",
  "tick": 123,
  "timeLimit": 3692,
  "note": "...",
  "players": [],
  "fakes": []
}
```

`players` chỉ chứa các player mà người nhận được phép thấy; `fakes` chỉ chứa fake prop trong tầm nhìn tương ứng.

## 7. Build, kiểm tra và mở rộng

```powershell
cabal build prophunt-server
```

Các phần nên bổ sung khi phát triển tiếp:

- frontend browser kết nối WebSocket và render map;
- test property cho movement, visibility, cooldown và điều kiện thắng;
- validate kích thước đội hình khi người chơi rời lobby;
- TLS reverse proxy (`wss://`) khi deploy Internet;
- chuẩn hóa encoding UTF-8 nếu terminal/editor hiển thị tiếng Việt sai.

## 8. Ghi chú thiết kế

- RNG là pseudo-random generator nội bộ nhận seed `Int`, thuận tiện cho replay và test deterministic.
- Engine dùng immutable record update; server mới là nơi quản lý concurrency và I/O.
- Bot Hunter chỉ đuổi Hider mà bot thực sự nhìn thấy; đường đi dùng BFS tránh tường.
- `Mode`, `whistle` và `bell` đã nằm trong model nhưng chưa được dùng đầy đủ trong logic hiện tại; có thể mở rộng cho AI và tín hiệu âm thanh sau này.
