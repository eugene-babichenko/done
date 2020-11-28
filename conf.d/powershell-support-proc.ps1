# This is the script containing all logic required for the WSL integration on
# the PowerShell side.
#
# Because PowerShell itself takes quite a long time to start and the scripts we
# used in the past contain some relatively heavy initialization, calling
# `powershell.exe -Command '...'` was long to the point of being irritating for
# something done on every command.
#
# Because of that, the current solution is to launch a background process that
# serves requests in a client-server fashion. The requests are fetched from
# `$InputPipe` which is reopened on each iteration. This is done because on the
# `fish` side the pipe is written to using `echo '...' > $InputPipe` which
# sends EOF after the command is completed. Thus, the pipe actually _needs_ to
# be reopened after each use. The output of commands is written to `stdout`
# which is managed by the calling side.
#
# The commands should be encoded in JSON in the following format:
# `{"Command": "CmdName",."Arguments": {...}}`. `Arguments` is not a required
# field. The output of each command is plaintext.
#
# The current commands are:
#
# * `GetForegroundWindow` - no arguments, outputs the current WID.
# * `ShowNotification` - display a native Windows notifcation. Arguments are
#    `SoundOpt` to enable or disable the notifcation sound (boolean), `Title`
#    and `Message` which are strings and the names are speaking for themselves.

param(
    [Parameter(Mandatory=$true)]
    [string] $InputPipe
)

Import-Module Microsoft.PowerShell.Utility -Function ConvertFrom-Json | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
[Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null

Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class WindowsCompat {
        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();
    }
"@

function Show-Notification([bool] $SoundOpt, [string] $Title, [string] $Message) {
    if ($SoundOpt) {
        $SoundOptStr = '<audio silent="false" src="ms-winsoundevent:Notification.Default" />'
    } else {
        $SoundOptStr = '<audio silent="true" />'
    }

    $ToastXmlSource = @"
    <toast>
        $SoundOptStr
        <visual>
            <binding template="ToastText02">
                <text id="1">$Title</text>
                <text id="2">$Message</text>
            </binding>
        </visual>
    </toast>
"@

    $ToastXml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $ToastXml.loadXml($ToastXmlSource)

    $Toast = New-Object Windows.UI.Notifications.ToastNotification $ToastXml

    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("fish").Show($Toast)
}

while ($true) {
    try {
        $CommandString = Get-Content -Path $InputPipe
    }
    catch [System.OperationCanceledException] {
        continue
    }

    $CommandString | ConvertFrom-Json -OutVariable Command | Out-Null

    if ($Command.Command -eq "GetForegroundWindow") {
        $Result = [WindowsCompat]::GetForegroundWindow()
        Write-Host "$Result"
    } elseif ($Command.Command -eq "ShowNotification") {
        $Arguments = $Command.Arguments
        Show-Notification -SoundOpt $Arguments.SoundOpt -Title $Arguments.Title -Message $Arguments.Message
        Write-Host "OK"
    }
}
