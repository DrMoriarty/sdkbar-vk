# Description
This plugin adds VKontakte integration for sdkbar plugin system.

# Installation

`sdkbar -i https://github.com/OrangeAppsRu/sdkbar-vk`

# Dependencies

This plugins depends on `sdkbar-utils` (https://github.com/OrangeAppsRu/sdkbar-utils).

# Plugin JS interface

- `vksdk.login(permissions_array, callback_function, callback_this)`
- `vksdk.logout()`
- `vksdk.loggedin()` returns bool
- `vksdk.users_get(params_dictionary, callback_function, callback_this)`
- `vksdk.friends_get(callback_function, callback_this)`
- `vksdk.friends_get(params_dictionary, callback_function, callback_this)`
- `vksdk.wall_post(params_dictionary, callback_function, callback_this)`
- `vksdk.call_api(method, params_dictionary, callback_function, callback_this)`
