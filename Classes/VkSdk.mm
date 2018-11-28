//
//  VkSdk.m
//
//  Created by Vasiliy on 17.04.17.
//
//

#import <Foundation/Foundation.h>
#import "VkSdk.h"
#import <VKSdk/VKSdk.h>
#include "scripting/js-bindings/manual/cocos2d_specifics.hpp"
#import <StoreKit/StoreKit.h>

static NSMutableArray *calls = nil;

// FROM JS VAL

static NSDictionary* jsval_to_dictionary(JSContext* cx, JS::HandleValue v)
{
    if (v.isNullOrUndefined())
    {
        return nil;
    }
    
    JS::RootedObject tmp(cx, v.toObjectOrNull());
    if (!tmp)
    {
        CCLOG("%s", "jsval_to_dictionary: the jsval is not an object.");
        return nil;
    }
    NSMutableDictionary *result = [NSMutableDictionary new];
    
    JS::RootedObject it(cx, JS_NewPropertyIterator(cx, tmp));
    
    while (true)
    {
        JS::RootedId idp(cx);
        JS::RootedValue key(cx);
        if (! JS_NextProperty(cx, it, idp.address()) || ! JS_IdToValue(cx, idp, &key))
        {
            return nil; // error
        }
        
        if (key.isNullOrUndefined())
        {
            break; // end of iteration
        }
        
        if (!key.isString())
        {
            continue; // only take account of string key
        }
        
        JSStringWrapper keyWrapper(key.toString(), cx);
        
        JS::RootedValue value(cx);
        JS_GetPropertyById(cx, tmp, idp, &value);
        NSString *keyString = [NSString stringWithUTF8String:keyWrapper.get()];
        if (value.isString()) {
            JSStringWrapper valueWrapper(value.toString(), cx);
            result[keyString] = [NSString stringWithUTF8String:valueWrapper.get()];
        } else if(value.isBoolean()) {
            result[keyString] = [NSNumber numberWithBool:value.get().toBoolean()];
        } else if(value.isDouble()) {
            result[keyString] = [NSNumber numberWithDouble:value.get().toDouble()];
        } else if(value.isInt32()) {
            result[keyString] = [NSNumber numberWithInteger:value.get().toInt32()];
        } else {
            CCASSERT(false, "jsval_to_dictionary: not supported map type");
        }
    }
    
    return result;
}

// TO JS VAL

static jsval object_to_jsval(JSContext *cx, id object);

static jsval string_to_jsval(JSContext *cx, NSString* string)
{
    return std_string_to_jsval(cx, std::string([string UTF8String]));;
}

static jsval number_to_jsval(JSContext *cx, NSNumber* number)
{
    return DOUBLE_TO_JSVAL(number.doubleValue);
}

static jsval array_to_jsval(JSContext *cx, NSArray* array)
{
    JS::RootedObject jsretArr(cx, JS_NewArrayObject(cx, array.count));
    
    int i = 0;
    for(id val in array) {
        JS::RootedValue arrElement(cx);
        arrElement = object_to_jsval(cx, val);
        if (!JS_SetElement(cx, jsretArr, i, arrElement)) {
            break;
        }
        ++i;
    }
    return OBJECT_TO_JSVAL(jsretArr);
}

static jsval dictionary_to_jsval(JSContext* cx, NSDictionary *dict)
{
    JS::RootedObject proto(cx);
    JS::RootedObject parent(cx);
    JS::RootedObject jsRet(cx, JS_NewObject(cx, NULL, proto, parent));

    for(NSString* key in dict.allKeys) {
        JS::RootedValue element(cx);
        
        id obj = dict[key];
        element = object_to_jsval(cx, obj);
        JS_SetProperty(cx, jsRet, [key UTF8String], element);
    }
    return OBJECT_TO_JSVAL(jsRet);
}

static jsval object_to_jsval(JSContext *cx, id object)
{
    if([object isKindOfClass:NSString.class]) {
        return string_to_jsval(cx, object);
    } else if([object isKindOfClass:NSDictionary.class]) {
        return dictionary_to_jsval(cx, object);
    } else if([object isKindOfClass:NSArray.class]) {
        return array_to_jsval(cx, object);
    } else if([object isKindOfClass:NSNumber.class]) {
        return number_to_jsval(cx, object);
    } else if([object isKindOfClass:NSNull.class]) {
        return JSVAL_NULL;
    } else {
        NSLog(@"Error: unknown value class %@", object);
        return JSVAL_NULL;
    }
}

/******************** VKCall ********************/

@interface VKCall: NSObject {
    VKRequest *vkRequest;
@public
    JSContext *context;
    mozilla::Maybe<JS::PersistentRootedObject> contextObject;
    mozilla::Maybe<JS::PersistentRootedValue> callback;
    mozilla::Maybe<JS::PersistentRootedValue> thisObject;
}

-(id) initWithRequest:(VKRequest*)request;
-(void) start;

@end

@implementation VKCall

-(id)initWithRequest:(VKRequest *)request
{
    if((self = [super init])) {
        vkRequest = request;
    }
    return self;
}

-(void) start
{
    [vkRequest executeWithResultBlock:^(VKResponse *response) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"VK Result: %@", response.json);
            JSAutoRequest rq(context);
            JSAutoCompartment ac(context, contextObject.ref());
            JS::RootedValue retVal(context);
            JS::AutoValueVector valArr(context);
            valArr.append(JSVAL_NULL);
            valArr.append(object_to_jsval(context, response.json));
            JS::HandleValueArray funcArgs = JS::HandleValueArray::fromMarkedLocation(2, valArr.begin());
            JS::RootedObject thisObj(context, thisObject.ref().get().toObjectOrNull());
            JS_CallFunctionValue(context, thisObj, callback.ref(), funcArgs, &retVal);
            [calls removeObject:self];
        });
    } errorBlock:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"VK Error: %@", error);
            JSAutoRequest rq(context);
            JSAutoCompartment ac(context, contextObject.ref());
            JS::RootedValue retVal(context);
            JS::AutoValueVector valArr(context);
            valArr.append(std_string_to_jsval(context, [error.description UTF8String]));
            valArr.append( JSVAL_NULL);
            JS::HandleValueArray funcArgs = JS::HandleValueArray::fromMarkedLocation(2, valArr.begin());
            JS::RootedObject thisObj(context, thisObject.ref().get().toObjectOrNull());
            JS_CallFunctionValue(context, thisObj, callback.ref(), funcArgs, &retVal);
            [calls removeObject:self];
        });
    }];
}

@end

/******************** VKDelegate ********************/

@interface VKDelegate: NSObject <VKSdkDelegate, VKSdkUIDelegate, SKProductsRequestDelegate> {
@public
    JSContext *loginContext;
    mozilla::Maybe<JS::PersistentRootedObject> loginContextObject;
    mozilla::Maybe<JS::PersistentRootedValue> loginCallback;
    mozilla::Maybe<JS::PersistentRootedValue> loginThisObject;
}

@end

@implementation VKDelegate

-(void)performRequest:(VKRequest*)request withBlock:(void(^)(NSString *error, NSDictionary* response))block
{
    [request executeWithResultBlock:^(VKResponse *response) {
        if(block) block(nil, response.json);
    } errorBlock:^(NSError *error) {
        NSLog(@"VK Error: %@", error);
        if(block) block(error.description, nil);
    }];
}

#pragma mark - VKSdkDelegate methods

- (void)vkSdkAccessAuthorizationFinishedWithResult:(VKAuthorizationResult *)result
{
    JSAutoCompartment ac(loginContext, loginContextObject.ref());
    JS::RootedObject thisObj(loginContext, loginThisObject.ref().get().toObjectOrNull());
    JS::AutoValueVector valArr(loginContext);
    if(result.error) {
        NSLog(@"VK Error: %@", result.error);
    } else if(result.token) {
        NSLog(@"VK login successfull with token: %@", result.token.accessToken);

        valArr.append( std_string_to_jsval(loginContext, [result.token.accessToken UTF8String]) );
        JS::HandleValueArray args = JS::HandleValueArray::fromMarkedLocation(1, valArr.begin());
        JS::RootedValue retval(loginContext);
        
        JS_CallFunctionValue(loginContext, thisObj, loginCallback.ref(), args, &retval);
    }
}

- (void)vkSdkUserAuthorizationFailed
{
    JSAutoCompartment ac(loginContext, loginContextObject.ref());
    JS::RootedObject thisObj(loginContext, loginThisObject.ref().get().toObjectOrNull());
    JS::AutoValueVector valArr(loginContext);
    valArr.append( std_string_to_jsval(loginContext, "VK Authorization Failed") );
    JS::HandleValueArray args = JS::HandleValueArray::fromMarkedLocation(1, valArr.begin());
    JS::RootedValue retval(loginContext);
    
    JS_CallFunctionValue(loginContext, thisObj, loginCallback.ref(), args, &retval);
}

- (void)vkSdkAccessTokenUpdated:(VKAccessToken *)newToken oldToken:(VKAccessToken *)oldToken
{
    NSLog(@"VK old token: %@ new token: %@", [oldToken accessToken], [newToken accessToken]);
}

- (void)vkSdkTokenHasExpired:(VKAccessToken *)expiredToken
{
    
}

#pragma mark - VKSdkUIDelegate methods

- (void)vkSdkShouldPresentViewController:(UIViewController *)controller
{
    [[UIApplication.sharedApplication.keyWindow rootViewController] presentViewController:controller animated:YES completion:nil];
}

- (void)vkSdkNeedCaptchaEnter:(VKError *)captchaError
{
    
}

- (void)vkSdkWillDismissViewController:(UIViewController *)controller
{
    
}

- (void)vkSdkDidDismissViewController:(UIViewController *)controller
{
    
}

#pragma mark Test

-(void)TestPurchase
{
    SKProductsRequest *req = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithObjects:@"coins_10", @"test", @"10Gold", @"50Gold", @"100Gold", @"200Gold", @"250Gold", @"500Gold", @"1000Gold", nil]];
    req.delegate = self;
    [req start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response NS_AVAILABLE_IOS(3_0);
{
    NSLog(@"Invalides: %@", response.invalidProductIdentifiers);
    NSLog(@"Products: %@", response.products);
}

@end

static VKDelegate * delegate = nil;

static bool jsb_vksdk_init(JSContext *cx, uint32_t argc, jsval *vp)
{
    JS::CallArgs args = JS::CallArgsFromVp(argc, vp);
    JS::RootedObject obj(cx, args.thisv().toObjectOrNull());
    js_proxy_t *proxy = jsb_get_js_proxy(obj);
    //PluginProtocol* cobj = (PluginProtocol *)(proxy ? proxy->ptr : NULL);
    //JSB_PRECONDITION2( cobj, cx, false, "Invalid Native Object");
    CCLOG("init, param count:%d.\n", argc);
    bool ok = true;
    if(argc == 1) {
        std::string arg0;
        JS::RootedValue arg0Val(cx, args.get(0));
        ok &= jsval_to_std_string(cx, arg0Val, &arg0);
        CCLOG("arg0: %s\n", arg0.c_str());
        calls = [NSMutableArray new];
        [VKSdk initializeWithAppId:[NSString stringWithUTF8String:arg0.c_str()]];
        delegate = [VKDelegate new];
        //[delegate TestPurchase];
        [VKSdk.instance registerDelegate:delegate];
        VKSdk.instance.uiDelegate = delegate;
        [VKSdk wakeUpSession:@[VK_PER_OFFLINE] completeBlock:^(VKAuthorizationState state, NSError *err) {
            if(err) {
                NSLog(@"VK init error: %@", err);
            }
            if(state == VKAuthorizationAuthorized) {
                NSLog(@"VK user authorized with token %@", [VKSdk accessToken].accessToken);
            }
        }];
        //cobj->callFuncWithParam(arg0.c_str(), NULL);
        return true;
    } else {
        JS_ReportError(cx, "Invalid number of arguments");
        return false;
    }
}

static bool jsb_vksdk_login(JSContext *cx, uint32_t argc, jsval *vp)
{
    JS::CallArgs args = JS::CallArgsFromVp(argc, vp);
    JS::RootedObject obj(cx, args.thisv().toObjectOrNull());
    CCLOG("init, param count:%d.\n", argc);
    bool ok = true;
    if(![VKSdk isLoggedIn]) {
        NSMutableArray *permissions = [NSMutableArray new];
        if(argc == 3) {
            // permissions, callback, this
            std::vector<std::string> arg0;
            JS::RootedValue arg0Val(cx, args.get(0));
            ok &= jsval_to_std_vector_string(cx, arg0Val, &arg0);
            if(arg0.size() > 0) {
                for(int i=0; i<arg0.size(); ++i) {
                    [permissions addObject:[NSString stringWithUTF8String:arg0[i].c_str()]];
                }
            }
            delegate->loginContext = cx;
            delegate->loginCallback.construct(cx, args.get(1));
            delegate->loginThisObject.construct(cx, args.get(2));
            delegate->loginContextObject.construct(cx, obj);
            CCLOG("permissions size: %d\n", (int)arg0.size());
        } else {
            JS_ReportError(cx, "Invalid number of arguments");
            return false;
        }
        if(permissions.count <= 0) {
            [permissions addObject:VK_PER_WALL];
            [permissions addObject:VK_PER_OFFLINE];
        }
        [VKSdk authorize:permissions];
    } else {
        NSString *token = VKSdk.accessToken.accessToken;
        JS::RootedValue retVal(cx);
        JS::AutoValueVector valArr(cx);
        valArr.append(object_to_jsval(cx, token));
        JS::HandleValueArray funcArgs = JS::HandleValueArray::fromMarkedLocation(1, valArr.begin());
        JS::RootedObject thisObj(cx, args.get(2).get().toObjectOrNull());
        JS_CallFunctionValue(cx, thisObj, args.get(1), funcArgs, &retVal);
    }
    return true;
}

static bool jsb_vksdk_logout(JSContext *cx, uint32_t argc, jsval *vp)
{
    if(argc == 0) {
        [VKSdk forceLogout];
        return true;
    } else {
        JS_ReportError(cx, "Invalid number of arguments");
        return false;
    }
}

static bool jsb_vksdk_loggedin(JSContext *cx, uint32_t argc, jsval *vp)
{
    if(argc == 0) {
        JS::CallReceiver rec = JS::CallReceiverFromVp(vp);
        
        // Access to the callee must occur before accessing/setting
        // the return value.
        JSObject &callee = rec.callee();
        rec.rval().set(JS::ObjectValue(callee));
        
        if([VKSdk isLoggedIn]) {
            rec.rval().set(JSVAL_TRUE);
        } else {
            rec.rval().set(JSVAL_FALSE);
        }
        return true;
    } else {
        JS_ReportError(cx, "Invalid number of arguments");
        return false;
    }
}

static bool jsb_vksdk_users_get(JSContext *cx, uint32_t argc, jsval *vp)
{
    JS::CallArgs args = JS::CallArgsFromVp(argc, vp);
    JS::RootedObject obj(cx, args.thisv().toObjectOrNull());
    if(argc == 3) {
        bool ok = true;
        JS::RootedValue arg0Val(cx, args.get(0));
        VKRequest *req = [[VKApi users] get:jsval_to_dictionary(cx, arg0Val)];
        VKCall *call = [[VKCall alloc] initWithRequest:req];
        [calls addObject:call];
        call->context = cx;
        call->contextObject.construct(cx, obj);
        call->callback.construct(cx, args.get(1));
        call->thisObject.construct(cx, args.get(2));
        [call start];
        return true;
    } else {
        JS_ReportError(cx, "Invalid number of arguments");
        return false;
    }
}

static bool jsb_vksdk_friends_get(JSContext *cx, uint32_t argc, jsval *vp)
{
    JS::CallArgs args = JS::CallArgsFromVp(argc, vp);
    JS::RootedObject obj(cx, args.thisv().toObjectOrNull());
    VKRequest *req = nil;
    if(argc == 2) {
        // callback function & this
        req = [[VKApi friends] get];
        VKCall *call = [[VKCall alloc] initWithRequest:req];
        [calls addObject:call];
        call->context = cx;
        call->contextObject.construct(cx, obj);
        call->callback.construct(cx, args.get(0));
        call->thisObject.construct(cx, args.get(1));
        [call start];
        return true;
    } else if(argc == 3) {
        // params, callback function & this
        JS::RootedValue arg0Val(cx, args.get(0));
        NSDictionary *friendsParams = jsval_to_dictionary(cx, arg0Val);
        req = [[VKApi friends] get:friendsParams];
        VKCall *call = [[VKCall alloc] initWithRequest:req];
        [calls addObject:call];
        call->context = cx;
        call->contextObject.construct(cx, obj);
        call->callback.construct(cx, args.get(1));
        call->thisObject.construct(cx, args.get(2));
        [call start];
        return true;
    } else {
        JS_ReportError(cx, "Invalid number of arguments");
        return false;
    }
}

static bool jsb_vksdk_wall_post(JSContext *cx, uint32_t argc, jsval *vp)
{
    JS::CallArgs args = JS::CallArgsFromVp(argc, vp);
    JS::RootedObject obj(cx, args.thisv().toObjectOrNull());
    VKRequest *req = nil;
    if(argc == 3) {
        // params, callback function & this
        bool ok = true;
        JS::RootedValue arg0Val(cx, args.get(0));
        NSDictionary *friendsParams = jsval_to_dictionary(cx, arg0Val);
        req = [[VKApi wall] post:friendsParams];
        VKCall *call = [[VKCall alloc] initWithRequest:req];
        [calls addObject:call];
        call->context = cx;
        call->contextObject.construct(cx, obj);
        call->callback.construct(cx, args.get(1));
        call->thisObject.construct(cx, args.get(2));
        [call start];
        return true;
    } else {
        JS_ReportError(cx, "Invalid number of arguments");
        return false;
    }
}

static bool jsb_vksdk_call_api(JSContext *cx, uint32_t argc, jsval *vp)
{
    JS::CallArgs args = JS::CallArgsFromVp(argc, vp);
    JS::RootedObject obj(cx, args.thisv().toObjectOrNull());
    if(argc == 4) {
        bool ok = true;
        std::string arg0;
        JS::RootedValue arg0Val(cx, args.get(0));
        ok &= jsval_to_std_string(cx, arg0Val, &arg0);
        NSString *method = [NSString stringWithUTF8String:arg0.c_str()];

        std::map<std::string, std::string> params;
        JS::RootedValue arg1Val(cx, args.get(1));
        NSDictionary *methodParams = jsval_to_dictionary(cx, arg1Val);

        VKRequest *req = [VKRequest requestWithMethod:method parameters:methodParams];
        VKCall *call = [[VKCall alloc] initWithRequest:req];
        [calls addObject:call];
        call->context = cx;
        call->contextObject.construct(cx, obj);
        call->callback.construct(cx, args.get(2));
        call->thisObject.construct(cx, args.get(3));
        [call start];
        return true;
    } else {
        JS_ReportError(cx, "Invalid number of arguments");
        return false;
    }
}

void register_all_vksdk_framework(JSContext* cx, JS::HandleObject obj)
{
    JS::RootedObject ns(cx);
    get_or_create_js_obj(cx, obj, "vksdk", &ns);

    JS_DefineFunction(cx, ns, "init", jsb_vksdk_init, 1, JSPROP_ENUMERATE | JSPROP_PERMANENT);
    JS_DefineFunction(cx, ns, "login", jsb_vksdk_login, 3, JSPROP_ENUMERATE | JSPROP_PERMANENT);
    JS_DefineFunction(cx, ns, "logout", jsb_vksdk_logout, 0, JSPROP_ENUMERATE | JSPROP_PERMANENT);
    JS_DefineFunction(cx, ns, "loggedin", jsb_vksdk_loggedin, 0, JSPROP_ENUMERATE | JSPROP_PERMANENT);
    JS_DefineFunction(cx, ns, "users_get", jsb_vksdk_users_get, 3, JSPROP_ENUMERATE | JSPROP_PERMANENT);
    JS_DefineFunction(cx, ns, "friends_get", jsb_vksdk_friends_get, 3, JSPROP_ENUMERATE | JSPROP_PERMANENT);
    JS_DefineFunction(cx, ns, "wall_post", jsb_vksdk_wall_post, 3, JSPROP_ENUMERATE | JSPROP_PERMANENT);
    JS_DefineFunction(cx, ns, "call_api", jsb_vksdk_call_api, 4, JSPROP_ENUMERATE | JSPROP_PERMANENT);

}
