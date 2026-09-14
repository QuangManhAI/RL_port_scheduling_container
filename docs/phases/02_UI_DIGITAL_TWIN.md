Bạn là senior frontend engineer + simulation engineer. Hãy đọc toàn bộ code hiện tại của project mô phỏng RL Port Scheduling Container. Mục tiêu là nâng cấp phần visualization/UI từ prototype đơn giản thành một mô phỏng cảng container đẹp, thực tế và dễ demo nghiên cứu hơn.

Yêu cầu quan trọng:

1. Không phá logic RL hiện tại

* Giữ nguyên hoặc tương thích với environment/state/action/reward hiện tại.
* Nếu cần đổi tên biến hoặc cấu trúc state, phải tạo adapter/mapping để không làm hỏng flow cũ.
* Các nút Reset, Step, Run, Manual/Agent mode, speed slider vẫn phải hoạt động.
* Khi Step hoặc Run, simulation phải cập nhật đúng time, total reward, last reward, status, current container, ships, cranes, event log.

2. Nâng cấp 3D Port View thành digital twin mini của cảng container
   Hãy thay visual hiện tại bằng một cảnh 3D đẹp và chân thực hơn, gồm:

* Mặt nước lớn có màu/texture nhẹ.
* Cầu cảng/bến neo rõ ràng.
* Ít nhất 1–2 tàu container đang cập bến hoặc đang chờ.
* Tàu phải có deck, khoang container, bridge/cabin.
* Quay crane đặt dọc mép cảng, có khung thép, boom, trolley/spreader.
* Yard blocks rõ ràng: Block A/B/C hoặc Block 0/1/2.
* Mỗi block có nhiều bay/stack, container được xếp thành tầng.
* Container có màu theo loại:

  * Import: xanh dương/teal.
  * Export: xanh lá.
  * Transshipment: cam/vàng.
* Có lane/đường chạy giữa quay crane và yard.
* Có truck/AGV nhỏ để vận chuyển container.
* Có yard crane hoặc RTG crane trong khu bãi.
* Thêm shadow, lighting, ambient light, directional light, fog nhẹ nếu phù hợp.
* Camera mặc định isometric/top-down 3D đẹp hơn, không quá xa và không quá trống.

3. Animation thực tế
   Khi agent hoặc user chọn action/stack:

* Container hiện tại phải được highlight.
* Nếu là import:
  ship/container source → quay crane nâng container → truck/AGV → yard stack → container đặt vào đúng vị trí.
* Nếu là export:
  yard stack → truck/AGV → quay crane → ship.
* Nếu là transshipment:
  ship/source → crane/truck → yard hoặc ship khác tùy logic state hiện tại.
* Animation có thể đơn giản nhưng phải mượt:

  * move container theo path.
  * crane trolley/spreader di chuyển.
  * truck/AGV chạy theo lane.
  * sau khi animation xong mới commit visual state.
* Nếu performance yếu, cho phép tắt animation bằng flag.

4. UI dashboard đẹp hơn
   Refactor giao diện tổng thể thành dashboard hiện đại:

* Header: PortEnv Monitor / Smart Port RL Digital Twin.
* KPI cards:

  * Time
  * Total Reward
  * Last Reward
  * Status
  * Avg ship waiting time nếu có state
  * Crane utilization nếu có state
  * Yard occupancy nếu có state
  * Rehandling count nếu có state
* Panel Current Decision:

  * Container ID
  * Type
  * Deadline
  * Priority
  * Weight
  * Selected Action
  * Suggested Action / Agent Action nếu có.
* Panel Ships:

  * ship id
  * arrival time
  * departure time
  * remaining containers
  * status: arrived/waiting/berthing/departed.
* Panel Cranes:

  * crane name
  * type: quay crane / yard crane
  * status: idle/busy
  * current task nếu có.
* Panel Reward Breakdown:

  * deadline reward/penalty
  * distance/yard placement reward
  * rehandling penalty
  * waiting penalty
  * crane idle penalty
    Nếu env chưa trả đủ breakdown thì hiển thị fallback “No detailed breakdown”.
* Event Log:

  * log từng step/action dưới dạng readable text.
  * auto-scroll xuống event mới nhất.

5. Interaction

* Click vào stack/bay trong 3D view hoặc grid bên dưới để chọn action.
* Selected stack phải được highlight bằng outline/glow.
* Stack không hợp lệ phải hiển thị disabled hoặc đỏ nhẹ.
* Hover vào stack/container hiển thị tooltip:

  * block
  * bay
  * tier
  * occupancy
  * container types đang chứa.
* Có legend màu container.
* Có nút đổi camera:

  * Overview
  * Follow Container
  * Crane View
  * Yard View
* Có nút toggle:

  * Show labels
  * Show paths
  * Show heatmap/occupancy nếu dễ làm.

6. Phần grid bên dưới
   Hiện tại grid block/bay khá đơn giản. Hãy làm nó giống yard planning board hơn:

* Mỗi block là một card riêng.
* Mỗi bay hiển thị nhiều tier/container.
* Màu container theo type.
* Hiển thị occupancy rõ ràng.
* Click bay chọn action.
* Bay đang chọn có border nổi bật.
* Nếu bay đầy thì disabled.

7. Thiết kế code sạch
   Hãy refactor code thành các component rõ ràng. Nếu dùng React/Next/Three.js/React Three Fiber thì đề xuất cấu trúc như sau, tùy project hiện tại mà áp dụng:

components/
port/
PortScene.tsx
WaterPlane.tsx
Berth.tsx
ShipModel.tsx
QuayCrane.tsx
YardCrane.tsx
ContainerBox.tsx
YardBlock.tsx
AGVTruck.tsx
CameraController.tsx
AnimationController.tsx
dashboard/
KpiCard.tsx
CurrentDecisionPanel.tsx
ShipsPanel.tsx
CranesPanel.tsx
RewardBreakdownPanel.tsx
EventLogPanel.tsx
ControlBar.tsx
YardPlanningGrid.tsx
state/
portTypes.ts
portStateAdapter.ts
simulationStore.ts

Yêu cầu:

* Tách data model/type rõ ràng.
* Không nhồi toàn bộ logic vào một file lớn.
* Có helper convert env state → render state.
* Có mock fallback data nếu env state thiếu field.
* Code phải readable, có comment ở các đoạn animation/state mapping khó hiểu.

8. Visual quality
   Phong cách mong muốn:

* Isometric realistic low-poly / semi-realistic industrial.
* Không quá cartoon.
* Màu nền hiện đại, sạch.
* UI có card, border, shadow nhẹ, spacing đẹp.
* Cảng phải có cảm giác “đang hoạt động”, không bị trống.
* Tối ưu để chạy mượt trên laptop phổ thông.

9. Performance

* Dùng instancing hoặc memoization nếu có nhiều container.
* Tránh re-render toàn bộ scene khi chỉ có KPI thay đổi.
* Animation dùng requestAnimationFrame/useFrame hợp lý.
* Không load asset ngoài nếu không cần. Ưu tiên dựng model bằng geometry cơ bản.
* Nếu project chưa có dependency cần thiết, chỉ thêm dependency hợp lý và giải thích trong output.

10. Compatibility

* Chạy được bằng lệnh dev hiện tại của project.
* Không để TypeScript error / lint error nghiêm trọng.
* Không để crash khi state thiếu field.
* Nếu không chắc env trả về gì, hãy inspect code trước rồi tạo adapter an toàn.

11. Output mong muốn sau khi sửa
    Sau khi code xong, hãy trả lời:

* Những file đã sửa/thêm.
* Cách chạy project.
* Những tính năng visualization đã thêm.
* Những field state nào đang được dùng.
* Nếu còn phần nào cần env backend bổ sung để simulation thực tế hơn, liệt kê rõ.

Hãy bắt đầu bằng việc đọc cấu trúc project, xác định framework đang dùng, tìm component hiện tại của PortEnv Monitor, sau đó refactor/nâng cấp theo yêu cầu trên. Không chỉ đổi CSS bề ngoài; phải nâng cấp cả scene 3D, layout dashboard, interaction và animation.
