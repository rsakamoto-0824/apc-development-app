function app = launchAPC()
%LAUNCHAPC Start the desktop app or the compiled standalone entry point.
app=APCDevelopmentApp;
if isdeployed, waitfor(app.Figure); end
end
