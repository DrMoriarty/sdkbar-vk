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
#include "platform/android/jni/JniHelper.h"
#include <jni.h>

void register_all_vksdk_framework(JSContext* cx, JS::HandleObject obj);

extern "C"
{
    void Java_org_cocos2dx_javascript_VkPlugin_loginResult(JNIEnv* env, jobject thiz, jint callbackId, jstring token);

    void Java_org_cocos2dx_javascript_VkPlugin_requestResult(JNIEnv* env, jobject thiz, jint callbackId, jstring err, jstring result);
};

#endif /* VkSdk_h */
