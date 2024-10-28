package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:thread"
import "core:time"
import "core:strconv"
import "core:math/rand"
import "core:math/linalg"
import "core:strings"
import "core:path/filepath"
import os "core:os/os2"
import sdl "vendor:sdl2"

wnds : [dynamic]^sdl.Window

main_window : ^sdl.Window
main_window_renderer : ^sdl.Renderer

main_time : f64

posters : [dynamic]Poster

ppath : string
get_pipe :: proc(flags: os.File_Flags) -> ^os.File {
	pipe_file : ^os.File
	if !os.exists(ppath) {
		os.make_directory(filepath.dir(ppath, context.temp_allocator))
		pipe_file, _ = os.create(ppath)
		fmt.printf("pip file created\n")
	} else {
		pipe_file, _ = os.open(ppath, flags, 0o666)
		fmt.printf("pip file opened\n")
	}
	return pipe_file
}

_buffer : [4 * 1024 * 1024]byte
pipe_file : ^os.File

main :: proc() {
	ppath = filepath.join({os.get_env("LOCALAPPDATA", context.temp_allocator), "/potraiter/.pipeman"}); defer delete(ppath)
	if len(os.args) <= 1 {
		main_host()
		return
	} else {
		main_client()
		return
	}
}

running := true

main_host :: proc() {
	posters = make([dynamic]Poster); defer delete(posters)

	pipe_file = get_pipe({ .Read, .Write }); defer os.close(pipe_file)
	os.truncate(pipe_file, 0)

	sdl.Init({.VIDEO})

	main_window = sdl.CreateWindow("server", 256, 256, 256, 256, {.HIDDEN})
	main_window_renderer = sdl.CreateRenderer(main_window, -1, {.ACCELERATED})

	fmt.printf("waiting for input...\n")
	event : sdl.Event
	for running {
		for sdl.PollEvent(&event) {
			if event.type == .WINDOWEVENT {
				we := event.window
				for &p in posters {
					if sdl.GetWindowID(p.window) == we.windowID {
						poster_handle_event(&p, event)
						break
					}
				}
			} else if event.type == .QUIT {
				running = false
			}
		}

		main_update(1.0/60.0)
	}

	sdl.Quit()
}

main_update :: proc(delta: f64) {
	if cmd := ppipe_read(pipe_file); cmd != {} {
		fmt.printf("{}\n", cmd)
		lines := strings.split_lines(cmd); defer delete(lines)
		host_handle_cmd(lines)
	}
	for i:int; i < len(posters); i += 1 {
		p := &posters[i]
		if p.kill {
			destroy_poster(p)
			ordered_remove(&posters, i)
		}
	}

	sdl.SetRenderDrawColor(main_window_renderer, 255, cast(u8)(rand.int31()%256), 0, 255)
	sdl.RenderClear(main_window_renderer)
	sdl.RenderPresent(main_window_renderer)

	for p in posters {
		sdl.RenderClear(p.renderer)
		sdl.RenderCopy(p.renderer, p.texture, {}, {})
		sdl.RenderPresent(p.renderer)
	}

	sdl.Delay(cast(u32)(delta*1000))
}


ppipe_read :: proc(pipe: ^os.File) -> string {
	n, err := os.read(pipe, _buffer[:])
	if err == nil || n != 0 {
		os.truncate(pipe, 0)
		os.seek(pipe, 0, .Start)
		return string(_buffer[:n])
	}
	return {}
}

Command :: union {
	CmdOpen, CmdExit,
}
CmdOpen :: struct {
	path : string,
}
CmdExit :: struct {
}

cmd : Command
option : PosterCreateOption
host_handle_cmd :: proc(args: []string) {
	if args[1] == "create" {
		path : string
		_arg_parser_vec2 :: proc(str: string, data: ^linalg.Vector2f64) -> bool {
			sp := strings.split(str, "x", context.temp_allocator)
			x, _ := strconv.parse_f64(sp[0])
			y, _ := strconv.parse_f64(sp[1])
			data^ = {x, y}
			return true
		}
		args_ok := args_read(args[1:],
			{argr_follow_by("create"), arga_set(&path)},
			{argr_prefix("-scale:"), arga_setp(&option.scale, _arg_parser_vec2)},
			{argr_prefix("-place:"), arga_action(
				proc(arg: string, user_data: rawptr) -> bool {
					sp := strings.split(arg, "x", context.temp_allocator)
					x, _ := strconv.parse_f64(sp[0])
					y, _ := strconv.parse_f64(sp[1])
					option.place = {x,y}
					return true
				}, nil)}
		)
		append(&posters, create_poster(path, option))
	} else if args[1] == "exit" {
		running = false
	}
}

main_client :: proc() {
	pipe_file := get_pipe({.Write}); defer os.close(pipe_file)
	using strings
	content : Builder
	builder_init(&content); defer builder_destroy(&content)

	for arg in os.args {
		write_string(&content, arg)
		write_rune(&content, '\n')
	}
	str := to_string(content)
	str = str[:len(str)-1]
	os.write(pipe_file, transmute([]u8)str)
}

create_window :: proc() {
	title := fmt.ctprintf("Window{}", len(wnds))
	wnd := sdl.CreateWindow(title, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED, 256, 256, { .SHOWN })
	append(&wnds, wnd)
}
