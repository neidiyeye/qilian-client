# iOS App Store 4.3 审核说明

## 当前实现

启连加速器的 Flutter 界面、账号与设备交互、Swift Network Extension、
Packet Tunnel 桥接、逻辑线路分配和服务端控制面均为项目自行开发。

客户端仅使用开源 `sing-box/Libbox` 作为网络协议引擎。iOS 客户端不使用
Hiddify，也不是远程网页壳。服务端源码、节点订阅地址、节点凭据和运营后台
不进入公开客户端仓库或安装包。

公开客户端源码：

`https://github.com/neidiyeye/qilian-client`

公开仓库固定使用 sing-box `v1.14.0`，commit
`0b8995879f29a9b98ee027bc17b75e101445b238`，并提供 Libbox 可复现构建脚本。

## Build 5 的产品差异

- 服务端管理的逻辑线路会在多个物理线路之间分配和故障切换。
- 智能模式使用版本化路由策略，客户端可以展示实际生效的策略版本和分流项。
- 路由策略控制国内域名、国内 IP、私网、DNS、IPv6 和域名识别行为。
- 系统 VPN 状态在 App 前后台之间同步，并支持控制面会话恢复。
- 账户包含会员、设备上限、在线上限、本机标识和公开用户 ID。
- 主页显示 Packet Tunnel 的实时上传、下载速率。
- Release 构建仅保留核心错误日志，不记录用户访问目标。

## 给 App Review 的回复

Hello App Review Team,

Thank you for your review.

Qilian Accelerator is our independently developed VPN product and this App
Store Connect record is intended to be its sole iOS distribution. The app is
not generated from a purchased template and is not a repackaged or rebranded
copy of another developer's app.

The app uses a locally bundled Flutter interface together with our native Swift
Network Extension and Packet Tunnel integration. It is not a remote web
wrapper. Our account and device management, membership enforcement, logical
location allocation, failover, versioned smart-routing policy, connection
recovery, system VPN state synchronization, and traffic accounting are
developed and operated by us.

The Packet Tunnel uses the open-source sing-box/Libbox project only as its
network protocol engine. The exact upstream revision and reproducible build
instructions are available in our public client source repository:

https://github.com/neidiyeye/qilian-client

Build 5 also exposes the effective smart-routing policy in the app, shows
real-time tunnel transfer rates, and includes clearer account and device
identity features.

The rejection message does not identify the app we were compared with or
whether the similarity was found in the binary, metadata, or product concept.
Could you please provide the specific app or elements considered similar so we
can address the concern accurately?

Thank you.
