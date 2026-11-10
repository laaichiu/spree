---
"@spree/sdk": patch
"@spree/admin-sdk": patch
"@spree/dashboard": patch
---

Expose independent phone-presence and phone-format settings through store settings and the Store API. When format validation is enabled, valid numbers are saved in E.164 format, and checkout rechecks saved addresses against the current store policy.
