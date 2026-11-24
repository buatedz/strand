# strand

fnf engine (barely) but its only for showcases. botplay is always on, you cant actually play
this is meant for running heavy fnf charts with low ram usage!! 

## stuff it has
- stack merging + skipping notes that are too close (both in options)
- charts get cached into one cache.bin
- stream json (streaming notes during the song)
- json and .thr charts (thr is from threadripper engine which isn't public yet soooo youll have to wait a bit)
- supports lua scripts that u can put in assets/scripts
- classic and hslice+js noteskins
- discord rpc
- it's a standalone exe, no dlls or anything (I HATE DLLS...)

## how to compile
if youre on windows, you need to have git, vs 2022 build tools (c++) and haxe installed!
next, in the folder you have the strand source code in, open cmd and type in these commands:
```cmd
haxelib setup C:\haxelib
haxelib install hxcpp 4.3.2
haxelib install lime 8.3.2
haxelib install openfl 9.5.2
haxelib install flixel 6.2.1
haxelib git hxluajit https://github.com/MAJigsaw77/hxluajit
haxelib run lime build windows
```
it should all be ready after that!

## how to use
open strand.exe preferably in an empty folder, it makes the assets folder and the settings.json for you
charts go in assets/data/songname, audio goes in assets/songs/songname you get it its the same as psych

only 4 key for now
