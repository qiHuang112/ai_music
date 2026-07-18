# AM-20260717-001 搜索聚合 UX 对齐

日期：2026-07-18
角色：mobile-ai-music-UX设计
结论：UX revision approved；真机状态证据最小 changes_requested

## Discovery 结论

| Entry | UX outcome | 结论 |
| --- | --- | --- |
| DISC-0005 | superseded | “扩展多个完整音频来源”的方向保留，但早期未确定的追加时机与范围已被 DISC-0006、DISC-0008、DISC-0009 的明确约束替代。 |
| DISC-0006 | integrated | Gequhai 优先、Kuwo 严格 HEAD + Range + 缓存校验、跨源去重，以及不展示待点击验证行，已进入设计与实现。 |
| DISC-0007 | integrated | 多来源搜索保持独立 request / Project Path，未混入 AM-005。 |
| DISC-0008 | integrated | 最新真机反馈已替代“首个候选立即单条出现”和“仅用户触底分页”：首批至少两条再发布，首屏最多串行补三页或达到八首，后续仍由触底加载。 |
| DISC-0009 | integrated | 本地完整缓存成为正式搜索来源并先于远端完成展示；额外来源只允许低频、严格、失败即闭路的准入评估，不得绕过防护，也不得把网盘、试听或挑战页当完整音频。 |

## UX 修订

1. **即时缓存**：命中本地完整缓存时，搜索提交后的第一次 UI 更新直接展示全部匹配缓存行；不等待远端、不显示行内校验态，播放与“已完成”状态立即可用。
2. **首屏批量增长**：在线结果不以“一次新增一首”的节奏发布。首批正常等待至少两条可用结果，随后每次至少新增两条；若来源全部完成，允许最后不足两条的尾批发布。
3. **有界首屏补量**：首次搜索最多串行请求三个聚合页，达到八首、来源耗尽或出错即停止。之后只有列表接近底部才加载下一页；同一来源页面不得并发。
4. **稳定 loading**：无结果时使用搜索入口/页面级加载；首批结果出现后，已有歌曲保持可点，后续校验与分页只占列表尾部固定 loading 行，不回退成整页阻塞。
5. **局部失败**：任一来源超时、403、429 或命中防护时，只关闭该来源并保留缓存/另一来源结果；已有结果时不得显示全页错误。只有本地缓存与所有在线来源均完成且没有结果时，才显示全空态。
6. **额外来源准入**：BuguYY、FLAC、22a5 当前均不进入 Auto。未来只有在真机上通过可达性、可信标题/歌手、HEAD、Range 206、完整缓存与失败回收证据后，才能单独申请进入；禁止绕过证书、挑战、安全验证或访问控制。

## 验收证据

- `dynamic-1s.xml/png`：首个可见在线批次已有多首，不出现单条增长；但 `dynamic-final` 与其可见内容相同，不能单独证明后续批量增长。
- `jay-cache-aggregation.xml/png`：周杰伦搜索首屏直接展示多条“已完成”缓存结果；`music_controller_test.dart` 的 `search publishes all matching complete cache before remote completion` 锁定远端未完成前即发布缓存，并可立即播放。
- `jay-cache-more.xml/png`：同一查询滚动后可见七里香、圣诞星、外婆、夜曲、晴天、花海、蜗牛、青花瓷、稻香等，证明目录已稳定增长到八首以上。
- `wangrong-cache-aggregation.xml/png` 与 `wangrong-final-no-keyboard.png`：缓存“哎呀”与多条严格校验后的在线结果共存；列表没有被后续加载覆盖或重排成空白。
- `wangrong-cache-aggregation-logcat.txt`：page 1/2/3 均串行完成，每页 3 条，非音频候选被拒绝；符合“三页或八首”的有界首屏补量。
- `device-network-and-source-admission.md`：小米真机 Gequhai 直连 TCP 超时；客户端按单源失败继续缓存与 Kuwo，并对 timeout/403/429/防护开启两分钟熔断。BuguYY、FLAC、22a5 均按 fail-closed 拒绝进入 Auto。
- `multi_source_search_coordinator_test.dart`：锁定首批/后续批量发布、单源失败保留成功结果、timeout/429 单源熔断且不阻塞另一来源。
- `music_home_page.dart`：首批为空时入口与顶栏加载；已有结果后 `isAppendingSearchResults` 只在列表尾部追加 `search-append-progress`，现有行保持在原列表中。

证据根目录：
`/Users/huangqi/AIHome/projects/ai_music_AM-20260717-001_multi_source_search_aggregation/evidence/qa-am001-multi-source-20260717`

## 风险与最小 changes_requested

- 当前证据没有捕获列表尾部 loading 的真机截图/XML；该状态只有代码与 widget/controller 测试支撑。
- 当前 Gequhai 超时来自设备侧探测说明，未与同一次 App 搜索的 UI 截图/XML/logcat 串成可追溯链路。
- 没有“本地无匹配 + 两个在线来源均完成无结果”的最终空态真机截图/XML。

Review 前只需补一组不改结构的真机状态证据：

1. 已有结果时截取尾部 `search-append-progress`，同时保留至少一条可点歌曲；附对应 XML。
2. 在同一次搜索链路中制造/记录 Gequhai 超时，证明 Kuwo 或本地结果仍保留且无全页错误；附 logcat + 截图/XML。
3. 记录一次三方均无结果后的最终空态，确认加载结束后才出现空态；附截图/XML。

补齐上述证据后，UX 可转为无条件 `accepted`；无需新增来源设置、来源标签或页面级错误提示。
