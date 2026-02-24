"""
外部支付网关测试脚本 — 模拟外部商户调用 API
用法: python test_payment.py

测试前先去 /credit/apps 创建应用，拿到 client_id 和 token 填到下面

注意：这是模拟真实的外部商户调用，会产生实际扣款。
如果只是想验证流程，请直接在应用页面点「测试支付」按钮。
"""
import hashlib
import hmac
import requests

# ========== 改成你的配置 ==========
BASE_URL = "https://sparkloc.com"
TOKEN = "tk_xxx"           # 应用页面复制的 Token
PAYMENT_ID = "pay_xxx"     # 应用页面复制的 client_id (Payment ID)
# ==================================

secret_key = hashlib.sha256(TOKEN.encode()).hexdigest()


def make_signature(params):
    param_string = "&".join(f"{k}={v}" for k, v in sorted(params.items()))
    return hmac.new(secret_key.encode(), param_string.encode(), hashlib.sha256).hexdigest()


def test_process_payment():
    """1. 发起支付"""
    params = {
        "amount": 10,
        "description": "测试支付",
        "order_id": "test_order_001",
    }
    params["signature"] = make_signature(params)

    resp = requests.post(f"{BASE_URL}/credit/payment/pay/{PAYMENT_ID}/process.json", data=params)
    print(f"[发起支付] status={resp.status_code}")
    print(resp.json())
    print()
    return resp.json()


def test_query(txn_id):
    """2. 查询交易状态"""
    params = {"transaction_id": txn_id}
    params["signature"] = make_signature(params)

    resp = requests.post(f"{BASE_URL}/credit/payment/query/{PAYMENT_ID}.json", data=params)
    print(f"[查询状态] status={resp.status_code}")
    print(resp.json())
    print()
    return resp.json()


if __name__ == "__main__":
    print("=" * 50)
    print("外部支付网关测试（模拟商户调用）")
    print("=" * 50)
    print()

    result = test_process_payment()

    txn_id = result.get("transaction_id")
    payment_url = result.get("payment_url")

    if payment_url:
        print(f"请用浏览器打开支付链接完成支付:")
        print(f"  {payment_url}")
        print()
        input("支付完成后按回车继续查询状态...")
        print()
        test_query(txn_id)
    else:
        print("发起支付失败，请检查配置")
