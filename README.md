# ExSubtitle - External Subtitle for Apple TV app on MacOS

How to install

1. Download and move exSubtitle.app to /Applications folder

2. Open terminal and run this code 

xattr -cr /Applications/ExSubtitle.app && codesign --force --deep --sign - /Applications/ExSubtitle.app

How to use

1. Open the Apple TV app and open the movie you want to watch.

2. Open ExSubtitle, press the shortcut Cmd + O (or select File > Open .srt file) to select the .srt subtitle file.

3. Enter the delay time (if any) or keep the default and press OK.

4. Press Play on Apple TV. Subtitles will automatically appear and play in sync at the bottom of the movie screen.

5. To customize the font, font size, background blur, spacing, etc., open the Settings of ExSubtitle.
