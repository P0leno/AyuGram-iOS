#import "AyuPythonRuntime.h"

#define PY_SSIZE_T_CLEAN
#import <Python/Python.h>

static __weak id<AyuPythonNativeDelegate> gNativeDelegate = nil;

static NSString *SafeNSStringFromCString(const char * _Nullable cstr) {
    if (cstr == NULL) {
        return @"";
    }
    NSString *result = [NSString stringWithUTF8String:cstr];
    return result ?: @"";
}

static PyObject *AyuNativeLog(PyObject *self, PyObject *args) {
    (void)self;
    const char *level = NULL;
    const char *pluginId = NULL;
    const char *message = NULL;
    if (!PyArg_ParseTuple(args, "sss", &level, &pluginId, &message)) {
        return NULL;
    }

    NSString *nsLevel = SafeNSStringFromCString(level);
    NSString *nsPluginId = SafeNSStringFromCString(pluginId);
    NSString *nsMessage = SafeNSStringFromCString(message);

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        [delegate pythonLogWithLevel:nsLevel pluginId:nsPluginId message:nsMessage];
    }
    Py_END_ALLOW_THREADS

    Py_RETURN_NONE;
}

static PyObject *AyuNativeGetSetting(PyObject *self, PyObject *args) {
    (void)self;
    const char *pluginId = NULL;
    const char *key = NULL;
    const char *defaultJSON = NULL;
    if (!PyArg_ParseTuple(args, "sss", &pluginId, &key, &defaultJSON)) {
        return NULL;
    }

    NSString *nsPluginId = SafeNSStringFromCString(pluginId);
    NSString *nsKey = SafeNSStringFromCString(key);
    NSString *nsDefault = SafeNSStringFromCString(defaultJSON);
    __block NSString *resultString = nsDefault;

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        resultString = [delegate pythonGetSettingForPlugin:nsPluginId key:nsKey defaultJSON:nsDefault] ?: nsDefault;
    }
    Py_END_ALLOW_THREADS

    const char *utf8 = [resultString UTF8String] ?: "";
    return PyUnicode_FromString(utf8);
}

static PyObject *AyuNativeSetSetting(PyObject *self, PyObject *args) {
    (void)self;
    const char *pluginId = NULL;
    const char *key = NULL;
    const char *valueJSON = NULL;
    if (!PyArg_ParseTuple(args, "sss", &pluginId, &key, &valueJSON)) {
        return NULL;
    }

    NSString *nsPluginId = SafeNSStringFromCString(pluginId);
    NSString *nsKey = SafeNSStringFromCString(key);
    NSString *nsValue = SafeNSStringFromCString(valueJSON);

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        [delegate pythonSetSettingForPlugin:nsPluginId key:nsKey valueJSON:nsValue];
    }
    Py_END_ALLOW_THREADS

    Py_RETURN_NONE;
}

static PyObject *AyuNativeShowBulletin(PyObject *self, PyObject *args) {
    (void)self;
    const char *title = NULL;
    const char *subtitle = NULL;
    const char *icon = NULL;
    if (!PyArg_ParseTuple(args, "sss", &title, &subtitle, &icon)) {
        return NULL;
    }

    NSString *nsTitle = SafeNSStringFromCString(title);
    NSString *nsSubtitle = SafeNSStringFromCString(subtitle);
    NSString *nsIcon = SafeNSStringFromCString(icon);

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        [delegate pythonShowBulletinWithTitle:nsTitle subtitle:nsSubtitle icon:nsIcon];
    }
    Py_END_ALLOW_THREADS

    Py_RETURN_NONE;
}

static PyObject *AyuNativeShowAlert(PyObject *self, PyObject *args) {
    (void)self;
    const char *title = NULL;
    const char *message = NULL;
    const char *buttonsJSON = NULL;
    if (!PyArg_ParseTuple(args, "sss", &title, &message, &buttonsJSON)) {
        return NULL;
    }

    NSString *nsTitle = SafeNSStringFromCString(title);
    NSString *nsMessage = SafeNSStringFromCString(message);
    NSString *nsButtons = SafeNSStringFromCString(buttonsJSON);

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        [delegate pythonShowAlertWithTitle:nsTitle message:nsMessage buttonsJSON:nsButtons];
    }
    Py_END_ALLOW_THREADS

    Py_RETURN_NONE;
}

static PyObject *AyuNativeSendMessage(PyObject *self, PyObject *args) {
    (void)self;
    const char *paramsJSON = NULL;
    if (!PyArg_ParseTuple(args, "s", &paramsJSON)) {
        return NULL;
    }

    NSString *nsParams = SafeNSStringFromCString(paramsJSON);
    __block NSString *resultString = @"{\"ok\":false,\"error\":\"no delegate\"}";

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        resultString = [delegate pythonSendMessageWithParamsJSON:nsParams] ?: @"{\"ok\":false}";
    }
    Py_END_ALLOW_THREADS

    const char *utf8 = [resultString UTF8String] ?: "{}";
    return PyUnicode_FromString(utf8);
}

static PyObject *AyuNativeExecuteRequest(PyObject *self, PyObject *args) {
    (void)self;
    const char *method = NULL;
    const char *paramsJSON = NULL;
    if (!PyArg_ParseTuple(args, "ss", &method, &paramsJSON)) {
        return NULL;
    }

    NSString *nsMethod = SafeNSStringFromCString(method);
    NSString *nsParams = SafeNSStringFromCString(paramsJSON);
    __block NSString *resultString = @"{\"ok\":false,\"error\":\"no delegate\"}";

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        resultString = [delegate pythonExecuteRequestWithMethod:nsMethod paramsJSON:nsParams] ?: @"{\"ok\":false}";
    }
    Py_END_ALLOW_THREADS

    const char *utf8 = [resultString UTF8String] ?: "{}";
    return PyUnicode_FromString(utf8);
}

static PyObject *AyuNativeGetCurrentAccountJSON(PyObject *self, PyObject *args) {
    (void)self;
    (void)args;
    __block NSString *resultString = @"{}";

    Py_BEGIN_ALLOW_THREADS
    id<AyuPythonNativeDelegate> delegate = gNativeDelegate;
    if (delegate != nil) {
        resultString = [delegate pythonGetCurrentAccountJSON] ?: @"{}";
    }
    Py_END_ALLOW_THREADS

    const char *utf8 = [resultString UTF8String] ?: "{}";
    return PyUnicode_FromString(utf8);
}

static PyMethodDef AyuNativeMethods[] = {
    {"log", AyuNativeLog, METH_VARARGS, "Log message to AyuGram plugin console"},
    {"get_setting", AyuNativeGetSetting, METH_VARARGS, "Read persisted JSON setting"},
    {"set_setting", AyuNativeSetSetting, METH_VARARGS, "Write persisted JSON setting"},
    {"show_bulletin", AyuNativeShowBulletin, METH_VARARGS, "Display Telegram bulletin toast"},
    {"show_alert", AyuNativeShowAlert, METH_VARARGS, "Display native alert dialog"},
    {"send_message", AyuNativeSendMessage, METH_VARARGS, "Send message through TelegramCore"},
    {"execute_request", AyuNativeExecuteRequest, METH_VARARGS, "Execute Telegram API request"},
    {"get_current_account_json", AyuNativeGetCurrentAccountJSON, METH_NOARGS, "Fetch active user metadata JSON"},
    {NULL, NULL, 0, NULL}
};

static struct PyModuleDef AyuNativeModuleDef = {
    PyModuleDef_HEAD_INIT,
    "_ayu_native",
    "Native iOS host bridge for exteraCompat plugins",
    -1,
    AyuNativeMethods
};

PyMODINIT_FUNC PyInit__ayu_native(void) {
    return PyModule_Create(&AyuNativeModuleDef);
}

static void AppendSearchPath(PyConfig *config, NSString *path) {
    if (path.length == 0) {
        return;
    }
    const char *utf8 = path.fileSystemRepresentation;
    if (utf8 == NULL) {
        return;
    }
    wchar_t *widePath = Py_DecodeLocale(utf8, NULL);
    if (widePath != NULL) {
        PyWideStringList_Append(&config->module_search_paths, widePath);
        PyMem_RawFree(widePath);
    }
}

static NSString *JSONErrorString(NSString *message) {
    NSDictionary *dict = @{
        @"ok": @NO,
        @"error": message ?: @"Unknown Python bridge error"
    };
    NSData *data = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (data == nil) {
        return @"{\"ok\":false,\"error\":\"serialization failure\"}";
    }
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{\"ok\":false}";
}

@implementation AyuPythonRuntime {
    dispatch_queue_t _initLockQueue;
    BOOL _initialized;
    PyObject *_hostModule;
}

+ (instancetype)sharedRuntime {
    static AyuPythonRuntime *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AyuPythonRuntime alloc] initPrivate];
    });
    return instance;
}

- (instancetype)initPrivate {
    self = [super init];
    if (self) {
        _initLockQueue = dispatch_queue_create("io.ayugram.python.lifecycle", DISPATCH_QUEUE_SERIAL);
        _initialized = NO;
        _hostModule = NULL;
    }
    return self;
}

- (void)setDelegate:(id<AyuPythonNativeDelegate>)delegate {
    gNativeDelegate = delegate;
}

- (id<AyuPythonNativeDelegate>)delegate {
    return gNativeDelegate;
}

- (BOOL)isInitialized {
    __block BOOL flag = NO;
    dispatch_sync(_initLockQueue, ^{
        flag = _initialized;
    });
    return flag;
}

- (BOOL)initializeWithBundlePath:(NSString *)bundlePath
                 extraSearchPath:(nullable NSString *)extraSearchPath
                           error:(NSError * _Nullable * _Nullable)error {
    __block BOOL success = NO;
    __block NSError *initError = nil;

    dispatch_sync(_initLockQueue, ^{
        if (_initialized) {
            success = YES;
            return;
        }

        NSString *pythonHome = [bundlePath stringByAppendingPathComponent:@"python"];
        NSString *sdkPath = [bundlePath stringByAppendingPathComponent:@"PythonSDK"];
        NSString *stdlibPath = [pythonHome stringByAppendingPathComponent:@"lib/python3.13"];
        NSString *dynloadPath = [stdlibPath stringByAppendingPathComponent:@"lib-dynload"];
        NSString *sitePackagesPath = [pythonHome stringByAppendingPathComponent:@"site-packages"];
        NSString *caCertPath = [sitePackagesPath stringByAppendingPathComponent:@"certifi/cacert.pem"];
        NSString *execPath = [NSBundle mainBundle].executablePath ?: [bundlePath stringByAppendingPathComponent:@"Telegram"];

        if (![[NSFileManager defaultManager] fileExistsAtPath:stdlibPath]) {
            initError = [NSError errorWithDomain:@"AyuPythonRuntime"
                                            code:1001
                                        userInfo:@{NSLocalizedDescriptionKey: @"Embedded Python stdlib missing from app bundle"}];
            return;
        }

        if ([[NSFileManager defaultManager] fileExistsAtPath:caCertPath]) {
            setenv("SSL_CERT_FILE", caCertPath.fileSystemRepresentation, 1);
            setenv("REQUESTS_CA_BUNDLE", caCertPath.fileSystemRepresentation, 1);
        }

        if (PyImport_AppendInittab("_ayu_native", PyInit__ayu_native) != 0) {
            initError = [NSError errorWithDomain:@"AyuPythonRuntime"
                                            code:1002
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to register _ayu_native builtin module"}];
            return;
        }

        PyPreConfig preconfig;
        PyPreConfig_InitIsolatedConfig(&preconfig);
        preconfig.utf8_mode = 1;
        PyStatus preStatus = Py_PreInitialize(&preconfig);
        if (PyStatus_Exception(preStatus)) {
            NSString *reason = SafeNSStringFromCString(preStatus.err_msg);
            initError = [NSError errorWithDomain:@"AyuPythonRuntime"
                                            code:1005
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Py_PreInitialize failed: %@", reason]}];
            return;
        }

        PyConfig config;
        PyConfig_InitIsolatedConfig(&config);
        config.write_bytecode = 0;
        config.install_signal_handlers = 0;
        config.parse_argv = 0;
        config.configure_c_stdio = 0;
        config.module_search_paths_set = 1;

        PyStatus status = PyConfig_SetBytesString(&config, &config.program_name, execPath.fileSystemRepresentation);
        if (!PyStatus_Exception(status)) {
            status = PyConfig_SetBytesString(&config, &config.executable, execPath.fileSystemRepresentation);
        }
        if (!PyStatus_Exception(status)) {
            status = PyConfig_SetBytesString(&config, &config.home, pythonHome.fileSystemRepresentation);
        }

        AppendSearchPath(&config, sdkPath);
        AppendSearchPath(&config, stdlibPath);
        AppendSearchPath(&config, dynloadPath);
        AppendSearchPath(&config, sitePackagesPath);
        if (extraSearchPath.length > 0) {
            AppendSearchPath(&config, extraSearchPath);
        }

        if (!PyStatus_Exception(status)) {
            status = Py_InitializeFromConfig(&config);
        }
        PyConfig_Clear(&config);

        if (PyStatus_Exception(status)) {
            NSString *reason = SafeNSStringFromCString(status.err_msg);
            initError = [NSError errorWithDomain:@"AyuPythonRuntime"
                                            code:1003
                                        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"Py_InitializeFromConfig failed: %@", reason]}];
            return;
        }

        _hostModule = PyImport_ImportModule("_ayu_runtime_host");
        if (_hostModule == NULL) {
            PyErr_Print();
            PyEval_SaveThread();
            initError = [NSError errorWithDomain:@"AyuPythonRuntime"
                                            code:1004
                                        userInfo:@{NSLocalizedDescriptionKey: @"Failed to import _ayu_runtime_host from PythonSDK"}];
            return;
        }

        // Release the GIL so Swift threads / Python worker threads can acquire via PyGILState_Ensure.
        PyEval_SaveThread();
        _initialized = YES;
        success = YES;
    });

    if (!success && error != NULL) {
        *error = initError;
    }
    return success;
}

- (NSString *)dispatchCommand:(NSString *)command payloadJSON:(NSString *)payloadJSON {
    if (!self.initialized || _hostModule == NULL) {
        return JSONErrorString(@"Python runtime not initialized");
    }

    PyGILState_STATE gilState = PyGILState_Ensure();
    NSString *response = nil;

    PyObject *dispatchFunc = PyObject_GetAttrString(_hostModule, "dispatch_json");
    if (dispatchFunc == NULL || !PyCallable_Check(dispatchFunc)) {
        Py_XDECREF(dispatchFunc);
        PyErr_Clear();
        PyGILState_Release(gilState);
        return JSONErrorString(@"_ayu_runtime_host.dispatch_json unavailable");
    }

    const char *cmdCStr = [command UTF8String] ?: "";
    const char *payloadCStr = [payloadJSON UTF8String] ?: "{}";
    PyObject *pyResult = PyObject_CallFunction(dispatchFunc, "ss", cmdCStr, payloadCStr);
    Py_DECREF(dispatchFunc);

    if (pyResult == NULL) {
        PyObject *ptype = NULL, *pvalue = NULL, *ptraceback = NULL;
        PyErr_Fetch(&ptype, &pvalue, &ptraceback);
        PyErr_NormalizeException(&ptype, &pvalue, &ptraceback);
        NSString *errDesc = @"Python invocation raised exception";
        if (pvalue != NULL) {
            PyObject *strObj = PyObject_Str(pvalue);
            if (strObj != NULL) {
                errDesc = SafeNSStringFromCString(PyUnicode_AsUTF8(strObj));
                Py_DECREF(strObj);
            }
        }
        Py_XDECREF(ptype);
        Py_XDECREF(pvalue);
        Py_XDECREF(ptraceback);
        response = JSONErrorString(errDesc);
    } else {
        if (PyUnicode_Check(pyResult)) {
            response = SafeNSStringFromCString(PyUnicode_AsUTF8(pyResult));
        } else {
            response = JSONErrorString(@"Unexpected non-string return from dispatch_json");
        }
        Py_DECREF(pyResult);
    }

    PyGILState_Release(gilState);
    return response ?: JSONErrorString(@"Empty bridge response");
}

- (void)shutdown {
    dispatch_sync(_initLockQueue, ^{
        if (!_initialized) {
            return;
        }
        PyGILState_Ensure();
        Py_XDECREF(_hostModule);
        _hostModule = NULL;
        _initialized = NO;
        Py_FinalizeEx();
    });
}

@end
