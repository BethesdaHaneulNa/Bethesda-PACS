# Bethesda CD - tests: the windows the tests drive are shown where nobody sees them.
# A person may be working at this PC while a test runs: the window is put far off the screen,
# kept out of the taskbar, and shown without taking the keyboard away from what the person
# is doing. Everything else is as with Show(): the window exists, is "visible" to its own
# code, can be drawn into a picture, and is told that it has been shown.
if (-not ('BethesdaTest.Win' -as [type])) {
  Add-Type -Namespace BethesdaTest -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int how);'
}
function Show-Quietly($form) {
  $form.StartPosition = 'Manual'; $form.Location = New-Object Drawing.Point(-20000, -20000); $form.ShowInTaskbar = $false
  $script:quietShown = $false; $form.add_Shown({ $script:quietShown = $true })
  [void][BethesdaTest.Win]::ShowWindow($form.Handle, 4)                 # 4 = shown, not made the active window
  [Windows.Forms.Application]::DoEvents()
  if (-not $script:quietShown) {                                        # shown this way, Windows Forms does not say "Shown" by itself
    $flags = [Reflection.BindingFlags]'Instance,NonPublic'
    [Windows.Forms.Form].GetMethod('OnShown', $flags).Invoke($form, @([EventArgs]::Empty))
    [Windows.Forms.Application]::DoEvents()
  }
}
