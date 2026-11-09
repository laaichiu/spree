---
"@spree/sdk": patch
"@spree/admin-sdk": patch
"@spree/dashboard": patch
---

Expose checkout address phone requirements and optional number validation to storefronts and store settings. Valid numbers are saved in E.164 format, and checkout rechecks saved addresses against the current store policy.
