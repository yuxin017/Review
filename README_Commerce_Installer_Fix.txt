修复：之前 03_APPLY_COMMERCE.py 会因为你按照说明提前复制新增文件而错误中断。

用本 ZIP 的 03_APPLY_COMMERCE.py 替换 FYP_New 根目录的同名 Python 脚本。
请连同 commerce_payload 文件夹一起解压到 FYP_New 根目录（仅是标准源文件备用副本）。
不要删除项目现有 functions/src/stripe_commerce_gateway.js、lib/commerce/stripe_commerce_client.dart 或 lib/visitor/pages/souvenir_shop_page.dart。

在 FYP_New PowerShell 中运行：
  python .\03_APPLY_COMMERCE.py

新脚本会核对现有 3 个文件是否与原安装包 SHA256 完全一致。如果一致，就保留这些文件并修改其余 8 个文件；如果不同，会停止避免覆盖你的工作。
不要再运行 01 或 02，也不要先部署 Rules。

注意：只确认安装脚本逻辑，不等于 Flutter、支付 Webhook 或 Firebase 在线联调已成功；安装后须执行 flutter analyze、node --check、git diff --check。
