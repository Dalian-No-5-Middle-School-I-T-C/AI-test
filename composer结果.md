# Composer 2.5

## 首次编译

报错：
```
> hvigor ERROR: ArkTS Compiler Error
1 ERROR: 10605040 ArkTS Compiler Error
Error Message: Object literals cannot be used as type declarations (arkts-no-obj-literals-as-types) At File: C:/Users/33554/Documents/learn/test/ark/composer/entry/src/main/ets/service/DeepSeekService.ets:36:14


2 ERROR: 10605040 ArkTS Compiler Error
Error Message: Object literals cannot be used as type declarations (arkts-no-obj-literals-as-types) At File: C:/Users/33554/Documents/learn/test/ark/composer/entry/src/main/ets/service/DeepSeekService.ets:44:11


COMPILE RESULT:FAIL {ERROR:3 WARN:21}

* Try:
> Run with --stacktrace option to get the stack trace.
> Run with --debug option to get more log output.

> hvigor ERROR: BUILD FAILED in 31 s 535 ms 

进程已结束，退出代码为 -1
```

## 修复编译错误

编译通过，但是发送消息之后模型没有回应，重新加载对话也不会显示

## 修复模型无法回复

现在重新加载对话才能够看到回复，看不到流式回复，工具调用流程能跑通。

## 修复流式回复问题

能够看到回复更新，但不是流式。

## 修复流式问题

它说“在 API 23 上，http.request() 往往不会逐 token 触发 dataReceive，而是一次性返回整段 SSE。所有 onContent 回调在同一帧内同步执行，UI 只会渲染最终结果，看起来就像“非流式”。”然后就用伪流式了。

其他功能正常。
