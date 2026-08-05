# exSubtitle - External Subtitle for Apple TV app on MacOS

A Mac app provides the ability to add external subtitles to the Apple TV app.

<img width="5274" height="2485" alt="IMG_3380" src="https://github.com/user-attachments/assets/714571cd-6df9-4af6-b4a1-709b00e825dd" />

## How to install

1. Download and move exSubtitle.app to /Applications folder

2. Open terminal and run this code 

`xattr -cr /Applications/ExSubtitle.app && codesign --force --deep --sign - /Applications/ExSubtitle.app`

## How to use

1. Open the Apple TV app and open the movie you want to watch.

2. Open exSubtitle, select the .srt subtitle file.

3. Enter the delay time (if any) or keep the default and press OK.

4. Press Play on Apple TV. Subtitles will automatically appear and play in sync at the bottom of the movie screen.

5. To customize the font, font size, background blur, spacing, etc., open the Settings of ExSubtitle.
