package org.cocos2dx.javascript;

import org.json.JSONException;
import org.json.JSONArray;
import org.json.JSONObject;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.content.Context;
import android.content.Intent;
import android.widget.Toast;
import android.util.Log;
import android.os.AsyncTask;
import android.app.AlertDialog;
import android.app.Activity;
import android.util.Base64;
import android.os.Handler;
import java.util.HashMap;
import java.util.Map;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.HttpURLConnection;

import com.vk.sdk.VKAccessToken;
import com.vk.sdk.VKSdk;
import com.vk.sdk.VKUIHelper;
import com.vk.sdk.VKCallback;
import com.vk.sdk.VKScope;
import com.vk.sdk.util.VKUtil;
import com.vk.sdk.api.VKApi;
import com.vk.sdk.api.VKApiConst;
import com.vk.sdk.api.VKError;
import com.vk.sdk.api.VKRequest;
import com.vk.sdk.api.VKRequest.VKRequestListener;
import com.vk.sdk.api.VKParameters;
import com.vk.sdk.api.VKResponse;
import com.vk.sdk.dialogs.VKCaptchaDialog;
import com.vk.sdk.dialogs.VKShareDialog;
import com.vk.sdk.api.photo.VKUploadImage;
import com.vk.sdk.api.photo.VKImageParameters;
import com.vk.sdk.util.VKJsonHelper;
import org.cocos2dx.lib.Cocos2dxHelper;
import android.preference.PreferenceManager.OnActivityResultListener;

public class VkPlugin {
    private static final String TAG = "VkPlugin";
    static final String sTokenKey = "VK_ACCESS_TOKEN";
    public static Activity appActivity;
    private static int loginCallbackId;
    private static final String dummyAnswer = "{\"ok\": true}";
    private static boolean inited = false;

	public static void init() {
        if(!inited) {
            appActivity = Cocos2dxHelper.getActivity();
            Log.i(TAG, "VK initialize");
            String[] fingerprints = VKUtil.getCertificateFingerprint(appActivity, appActivity.getPackageName());
			Log.i(TAG, "package: " + appActivity.getPackageName());
			Log.i(TAG, "fingerprints: " + fingerprints[0]);
            VKSdk.initialize(appActivity.getApplicationContext());
            Cocos2dxHelper.addOnActivityResultListener(new OnActivityResultListener() {
                    @Override
                    public boolean onActivityResult(int requestCode, int resultCode, Intent data) {
                        VkPlugin.onActivityResult(requestCode, resultCode, data);
                        return true;
                    }
                });
            inited = true;
        }
    }

    public static boolean login(String[] permissions, int callbackId)
    {
        init();
        if(VKSdk.isLoggedIn()) {
            String token = VKSdk.getAccessToken().accessToken;
            callLoginResult(callbackId, token);
        } else {
            loginCallbackId = callbackId;
            VKSdk.login(appActivity, permissions);
        }
        return true;
    }

    public static boolean logout()
    {
        init();
        VKSdk.logout();
        return true;
    }

    public static boolean isLoggedIn()
    {
        init();
        return VKSdk.isLoggedIn();
    }

    public static void onActivityResult(int requestCode, int resultCode, Intent data)
    {
        init();
        if(resultCode == Activity.RESULT_CANCELED && data == null) {
            // switch to another activity result callback
            return;
        }
        Log.i(TAG, "onActivityResult(" + requestCode + "," + resultCode + "," + data);
        VKSdk.onActivityResult(requestCode, resultCode, data, new VKCallback<VKAccessToken>() {
                @Override
                public void onResult(VKAccessToken res) {
                    // User passed Authorization
                    final String token = res.accessToken;
                    final String email = res.email;
                    Log.i(TAG, "VK new token: "+token);
                    res.saveTokenToSharedPreferences(appActivity, sTokenKey);
                    callLoginResult(loginCallbackId, token);
                }

                @Override
                public void onError(VKError error) {
                    // User didn't pass Authorization
                    String err = error.toString();
                    Log.e(TAG, "VK Authorization error! "+err);
                    //new AlertDialog.Builder(getApplicationContext()).setMessage(error.errorMessage).show();
                    callLoginResult(loginCallbackId, null);
                }
            });
    }
  
    static public boolean usersGet(String arg, int callbackId) {
        init();
        try {
            JSONObject json = new JSONObject(arg);
            Map<String, Object> params = VKJsonHelper.toMap(json);
            VKRequest req = VKApi.users().get(new VKParameters(params));
            performRequest(req, callbackId);
            return true;
        } catch(Exception ex) {
            Log.e(TAG, ex.toString());
            return false;
        }
    }

    static public boolean wallPost(String arg, int callbackId) {
        init();
        Log.i(TAG, "wallPost arg:"+arg);
        try {
            JSONObject json = new JSONObject(arg);
            Map<String, Object> params = VKJsonHelper.toMap(json);
            VKRequest req = VKApi.wall().post(new VKParameters(params));
            performRequest(req, callbackId);
            return true;
        } catch(Exception ex) {
            Log.e(TAG, ex.toString());
            return false;
        }
    }

    static public boolean friendsGet(String arg, int callbackId) {
        init();
        try {
            JSONObject json = new JSONObject(arg);
            Map<String, Object> params = VKJsonHelper.toMap(json);
            VKRequest req = VKApi.friends().get(new VKParameters(params));
            performRequest(req, callbackId);
            return true;
        } catch(Exception ex) {
            Log.e(TAG, ex.toString());
            return false;
        }
    }

    static public boolean callApiMethod(String method, String arg, int callbackId) {
        init();
        Log.i(TAG, "callApiMethod:"+method+" arg:"+arg);
        try {
            JSONObject json = new JSONObject(arg);
            Map<String, Object> params = VKJsonHelper.toMap(json);
            VKRequest req = new VKRequest(method, new VKParameters(params));
            performRequest(req, callbackId);
            return true;
        } catch(Exception ex) {
            Log.e(TAG, ex.toString());
            return false;
        }
    }

    static private void performRequest(VKRequest request, final int callbackId) {
        request.executeWithListener(new VKRequestListener() {
                @Override
                public void onComplete(VKResponse response) {
                    try {
                        String result;
                        JSONObject o = response.json;
                        result = o.get("response").toString();
                        Log.i(TAG, result);
                        callRequestResult(callbackId, null, result);
                    } catch (JSONException e) {
                        Log.e(TAG, "JSON exception:", e);
                        callRequestResult(callbackId, e.toString(), null);
                    }
                }
                @Override
                public void onError(VKError error) {
                    String err = error.toString();
                    Log.e(TAG, err);
                    callRequestResult(callbackId, err, null);
                }
                @Override
                public void onProgress(VKRequest.VKProgressType progressType,
                                       long bytesLoaded,
                                       long bytesTotal)
                {
                    //I don't really believe in progress
                }
                @Override
                public void attemptFailed(VKRequest request, int attemptNumber, int totalAttempts) {
                    //More luck next time
                }
            });
    }

    static private void callLoginResult(final int callbackId, final String token) {
        //AsyncTask.execute(new Runnable() {
        appActivity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    loginResult(callbackId, token);
                }
            });
    }

    static private void callRequestResult(final int callbackId, final String error, final String result) {
        //AsyncTask.execute(new Runnable() {
        appActivity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    requestResult(callbackId, error, result);
                }
            });
    }

    public static native void loginResult(int callbackId, String token);
    public static native void requestResult(int callbackId, String err, String result);

}
