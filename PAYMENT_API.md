# Sparkloc 积分支付 API 对接指南

## 概述

Sparkloc 提供外部支付网关，允许第三方网站/应用通过 API 接入积分支付系统。用户在你的网站下单后，跳转到 Sparkloc 完成积分支付，支付成功后自动跳转回你的网站。

## 准备工作

1. 登录 Sparkloc，进入 [我的应用](https://sparkloc.com/credit/apps) 页面
2. 点击「创建应用」，填写应用名称和回调地址
3. 创建成功后获得：
   - **Payment ID** (`client_id`) — 应用唯一标识，用于 API 请求路径
   - **Token** (`tk_xxx`) — 用于生成签名密钥，务必妥善保管

## 测试模式

在应用管理页面点击「开启测试」，开启后：
- 通过该应用发起的所有交易自动标记为测试交易
- 允许自己给自己支付（正式模式下禁止）
- **不会产生实际的余额扣除和增加**
- 会正常生成订单记录和回调
- 对接调试完成后，关闭测试模式即可上线

---

## 签名算法

所有 API 请求都需要签名验证，签名算法如下：

### 步骤

1. 准备需要签名的参数（不包含 `signature` 本身）
2. 按参数名**字母顺序**排列
3. 拼接为 `key1=value1&key2=value2&key3=value3` 格式
4. 计算密钥：`secret_key = SHA256(your_token)`
5. 生成签名：`signature = HMAC-SHA256(secret_key, param_string)`

### 重要

- `your_token` 是创建应用时获得的 Token（格式 `tk_xxx`）
- `secret_key` 是 Token 的 SHA256 哈希（64位十六进制字符串）
- **不要直接用 Token 作为 HMAC 密钥**

### 示例（Python）

```python
import hashlib
import hmac

token = "tk_xxxxxxxxxxxx"
secret_key = hashlib.sha256(token.encode()).hexdigest()

params = {
    "amount": 100,
    "description": "购买VIP会员",
    "order_id": "order_20260224_001",
}

param_string = "&".join(f"{k}={v}" for k, v in sorted(params.items()))
# amount=100&description=购买VIP会员&order_id=order_20260224_001

signature = hmac.new(secret_key.encode(), param_string.encode(), hashlib.sha256).hexdigest()
```

---

## API 接口

### 1. 发起支付

由你的**服务端**调用，创建一笔待支付交易。

```
POST https://sparkloc.com/credit/payment/pay/{payment_id}/process.json
```

#### 请求参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| amount | Integer | 是 | 支付金额（积分），必须大于 0 |
| description | String | 是 | 交易描述，最长 500 字符 |
| order_id | String | 是 | 你的订单号（唯一标识） |
| signature | String | 是 | HMAC-SHA256 签名 |

#### 签名参数

```
amount=100&description=购买VIP会员&order_id=order_20260224_001
```

#### 成功响应

```json
{
  "payment_url": "https://sparkloc.com/credit/payment/pay/txn_xxx",
  "transaction_id": "txn_xxx",
  "status": "pending",
  "amount": 100,
  "is_test": false
}
```

#### 幂等性

同一个 `order_id` 重复请求：
- 如果已有 pending 且未过期的交易，返回该交易信息（不会重复创建）
- 如果已有非 pending 状态的交易，返回 409 错误

---

### 2. 跳转支付

将用户浏览器重定向到响应中的 `payment_url`：

```
https://sparkloc.com/credit/payment/pay/txn_xxx
```

用户会：
1. 如未登录，自动跳转到登录页
2. 登录后返回支付页面
3. 看到交易金额、描述、手续费等信息
4. 输入支付密码确认支付
5. 支付成功后自动跳转到你设置的回调地址

---

### 3. 处理回调

**重要：这是浏览器 GET 跳转，不是服务器 POST 请求！**

支付成功后，用户浏览器会跳转到你设置的回调地址，所有参数以查询字符串形式传递。

#### 回调 URL 示例

```
https://example.com/callback?
  transaction_id=txn_xxx&
  external_reference=order_20260224_001&
  amount=100&
  platform_fee=1&
  merchant_points=99&
  status=completed&
  paid_at=2026-02-24T12:00:00Z&
  signature=abc123...
```

#### 回调参数

| 参数 | 类型 | 说明 |
|------|------|------|
| transaction_id | String | 交易 ID |
| external_reference | String | 你的订单号（即发起时的 order_id） |
| amount | Integer | 支付金额（积分） |
| platform_fee | Integer | 平台手续费（积分） |
| merchant_points | Integer | 商家实际收到的积分 |
| status | String | 交易状态（completed） |
| paid_at | DateTime | 支付时间（ISO 8601） |
| signature | String | 回调签名 |

#### 验证回调签名

**必须验证签名，防止伪造请求！**

1. 从 URL 参数中取出 `signature`
2. 将**其余所有参数**按 key 字母排序拼接
3. 用 `HMAC-SHA256(secret_key, param_string)` 计算签名
4. 比对计算出的签名与收到的 `signature` 是否一致

签名参数示例：
```
amount=100&external_reference=order_20260224_001&merchant_points=99&paid_at=2026-02-24T12:00:00Z&platform_fee=1&status=completed&transaction_id=txn_xxx
```

#### 处理订单

验证签名通过后：
1. ✅ 检查幂等性 — 确保订单未被重复处理
2. ✅ 验证金额 — 确认 amount 与你的订单金额一致
3. ✅ 更新订单状态 — 标记为已支付
4. ✅ 执行业务逻辑 — 发货、开通服务等
5. ✅ 显示确认页面 — 向用户展示支付成功信息

---

### 4. 查询交易状态

如果回调失败或需要主动确认支付状态，可以使用查询接口。

```
POST https://sparkloc.com/credit/payment/query/{payment_id}.json
```

#### 请求参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| transaction_id | String | 是 | 交易 ID |
| signature | String | 是 | HMAC-SHA256 签名 |

#### 签名参数

```
transaction_id=txn_xxx
```

#### 成功响应

```json
{
  "transaction_id": "txn_xxx",
  "status": "completed",
  "amount": 100,
  "platform_fee": 1,
  "merchant_points": 99,
  "description": "购买VIP会员",
  "external_reference": "order_20260224_001",
  "created_at": "2026-02-24T12:00:00Z",
  "updated_at": "2026-02-24T12:05:00Z",
  "paid_at": "2026-02-24T12:05:00Z",
  "expires_at": "2026-02-24T12:30:00Z",
  "expired": false,
  "error_message": null
}
```

---

## 交易状态

| 状态 | 说明 |
|------|------|
| pending | 等待用户支付 |
| completed | 支付成功 |
| expired | 已过期（30分钟未支付） |
| failed | 支付失败 |
| cancelled | 已取消 |
| refunded | 已退款 |

---

## 完整对接示例（Python）

```python
import hashlib
import hmac
import requests

# 配置
BASE_URL = "https://sparkloc.com"
TOKEN = "tk_xxxxxxxxxxxx"
PAYMENT_ID = "pay_xxxxxxxxxxxx"

secret_key = hashlib.sha256(TOKEN.encode()).hexdigest()


def make_signature(params):
    param_string = "&".join(f"{k}={v}" for k, v in sorted(params.items()))
    return hmac.new(
        secret_key.encode(), param_string.encode(), hashlib.sha256
    ).hexdigest()


# 1. 发起支付
params = {
    "amount": 100,
    "description": "购买VIP会员",
    "order_id": "order_20260224_001",
}
params["signature"] = make_signature(params)

resp = requests.post(
    f"{BASE_URL}/credit/payment/pay/{PAYMENT_ID}/process.json",
    data=params,
)
data = resp.json()
print(f"支付链接: {data['payment_url']}")
# 将用户重定向到 data["payment_url"]


# 2. 验证回调签名（在你的回调接口中）
def verify_callback(query_params):
    received_sig = query_params.pop("signature")
    expected_sig = make_signature(query_params)
    return hmac.compare_digest(expected_sig, received_sig)


# 3. 查询交易状态（可选）
txn_id = data["transaction_id"]
query_params = {"transaction_id": txn_id}
query_params["signature"] = make_signature(query_params)

resp = requests.post(
    f"{BASE_URL}/credit/payment/query/{PAYMENT_ID}.json",
    data=query_params,
)
print(resp.json())
```

---

## 安全建议

1. **保护密钥** — Token 不要硬编码在前端代码中，使用环境变量或密钥管理服务
2. **使用 HTTPS** — 回调地址必须是 HTTPS
3. **验证签名** — 所有回调请求必须验证签名，签名不匹配时拒绝请求
4. **防止重复处理** — 用 order_id 做幂等检查，防止重复发货
5. **验证金额** — 回调金额必须与你的订单金额一致
6. **日志记录** — 记录所有支付相关操作和回调请求

## 常见问题

**Q: 签名验证失败？**
检查：Token 是否正确、参数排序是否按字母顺序、是否用了 SHA256(token) 作为 HMAC 密钥而不是直接用 token。

**Q: 回调没有收到？**
回调是浏览器 GET 跳转，如果用户关闭了浏览器就不会触发。建议用查询接口做定时轮询作为补救。

**Q: 订单会过期吗？**
会，未支付的交易 30 分钟后自动过期。过期后需要重新发起支付。

**Q: 同一个 order_id 可以重复使用吗？**
如果之前的交易还在 pending 且未过期，会返回已有交易信息。如果已完成/过期/失败，会返回 409 错误，需要换一个新的 order_id。
