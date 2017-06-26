//
//  VkSdk.h
//
//  Created by Vasiliy on 17.04.17.
//
//

#ifndef VkSdk_h
#define VkSdk_h

#include "base/ccConfig.h"
#include "jsapi.h"
#include "jsfriendapi.h"


void register_all_vksdk_framework(JSContext* cx, JS::HandleObject obj);


#endif /* VkSdk_h */
