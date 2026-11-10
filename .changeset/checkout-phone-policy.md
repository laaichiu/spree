---
"@spree/sdk": patch
"@spree/admin-sdk": patch
"@spree/dashboard": patch
---

Expose independent phone-presence and phone-format settings through store settings and the Store API. Existing stores that required a phone keep their previous effective format-validation behavior on upgrade unless they have already set the new preference. When format validation is enabled, valid numbers are saved in E.164 format, and checkout rechecks saved addresses against the current store policy.
