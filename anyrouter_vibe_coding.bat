@echo off
rem 强制声明 UTF-8 编码，防止中文变成乱码
chcp 65001 > nul

echo =========================================
echo      正在启动 Claude (AnyRouter 模式)
echo =========================================

:: 清除可能冲突的全局变量
set ANTHROPIC_API_KEY=

:: 【已修改】自动为你绑定 Clash 的默认代理端口 7890
set http_proxy=http://127.0.0.1:7890
set https_proxy=http://127.0.0.1:7890

:: 调用我们在第一步创建的专属配置文件
claude --settings "%USERPROFILE%\.claude\settings.anyrouter.json" --dangerously-skip-permissions

echo =========================================
echo      Claude 已退出
echo =========================================
pause