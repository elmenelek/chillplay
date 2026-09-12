chillplay
=========

A tiny terminal app I made because I wanted lofi playing in the background
while I code, without opening a browser tab, without a bloated app, and
without leaving my keyboard. You just type "chillplay" in any terminal and
you get a full-screen animated terminal UI with music streaming in the
background, right there next to your code.

Type "chillplay" anywhere in your terminal. That's it. It plays chill
music, shows a live animated ASCII scene, and gives you a tiny menu you can
control without ever touching a mouse. Ctrl+C stops it instantly, music and
all.


WHAT IT ACTUALLY DOES
----------------------

- Streams free, legal internet radio (via SomaFM) - no downloads, no files
  on your disk, just a live stream. There are 10 "vibes" to pick from:
  Chill, Relaxing, Calming, Dreamy, Retro, Vaporwave, Space, Drone, Rave,
  and Trance. Switch anytime without restarting the app.

- Animates a little ASCII scene while you listen, plus a live equalizer
  bar underneath. There are 4 themes:
    - Coffee     a steaming cup, slowly wafting
    - Rain       a gray cloud dropping blue rain
    - Hacker     green Matrix-style code rain (yes, with actual Chinese
                 characters mixed in, like the real thing)
    - Cyberpunk  a neon synthwave scene.. Sun, palm trees, a car, and a
                 scrolling grid floor

  Press [2] anytime to switch themes, or let it pick one at random.

- Built-in focus timer. Press [3], type how many minutes you want (say,
  25), and a countdown appears in the corner while you
  work. When it hits zero, the music stops, the screen clears, and it
  just says "Time's up." no popups, no sound effects, just a clean stop.

- Press [4] to pop open my GitHub profile in your browser.

- Ctrl+C at any time kills it instantly - the music does not keep playing
  in the background after you close it, even if something goes wrong.



HOW TO INSTALL IT (Windows)
-----------------------------

You need two things: Scoop (a simple package manager for Windows) and mpv
(a lightweight, free media player) to actually play the audio stream.
Everything else is just this script.

1. If you don't already have Scoop, open PowerShell and run:

     iwr -useb get.scoop.sh | iex

2. Install mpv:

     scoop install mpv

3. Download this repo (or just grab chillplay.ps1 and chillplay.cmd) and
   drop both files into a folder that's on your PATH. If you don't have
   one yet, the easiest way:

     New-Item -ItemType Directory -Force $HOME\.local\bin
     [Environment]::SetEnvironmentVariable(
         "Path",
         [Environment]::GetEnvironmentVariable("Path","User") + ";$HOME\.local\bin",
         "User"
     )

   Then copy chillplay.ps1 and chillplay.cmd into that folder
   ($HOME\.local\bin).

4. Open a brand new terminal window (so it picks up the PATH change) and
   just type:

     chillplay

That's it. No installer, no background service, nothing running when
you're not using it.

ChillPlay
<img width="646" height="623" alt="chillplay-demo" src="https://github.com/user-attachments/assets/7b9eb269-f809-49f8-ab51-e6214db909fe" />


NOTES
------

- Windows only
- All the streams are free
- Works in PowerShell and cmd.exe.
