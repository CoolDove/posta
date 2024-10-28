package main

import "base:runtime"
import "core:fmt"
import "core:io"
import "core:thread"
import "core:time"
import "core:math/linalg"
import "core:strings"
import "core:path/filepath"
import os "core:os/os2"
import sdl "vendor:sdl2"
import sdlimg "vendor:sdl2/image"

Poster :: struct {
	name : string,
	window : ^sdl.Window,
	renderer : ^sdl.Renderer,
	surface : ^sdl.Surface,
	texture : ^sdl.Texture,
	kill : bool,
} 

PosterCreateOption :: struct {
	scale, place : linalg.Vector2f64,
}

create_poster :: proc(path: string, option: PosterCreateOption) -> Poster {
	path := strings.clone_to_cstring(path); defer delete(path)
	poster : Poster
	using poster
	name = strings.clone(filepath.short_stem(cast(string)path))
	surface = sdlimg.Load(path)
	w, h := surface.clip_rect.w, surface.clip_rect.h
	if option.scale != {} do w, h = cast(i32)(cast(f64)w * option.scale.x), cast(i32)(cast(f64)h * option.scale.y)
	window = sdl.CreateWindow(path, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED, w, h, {.SHOWN, .RESIZABLE, .SKIP_TASKBAR, .ALWAYS_ON_TOP , .UTILITY})
	renderer = sdl.CreateRenderer(window, -1, sdl.RENDERER_ACCELERATED)
	assert(renderer != nil, fmt.tprintf("Failed to create renderer: {}", sdl.GetError()))
	texture = sdl.CreateTextureFromSurface(renderer, surface)
	return poster
}

destroy_poster :: proc(using poster: ^Poster) {
	using sdl
	delete(name)
	DestroyTexture(texture)
	DestroyRenderer(renderer)
	DestroyWindow(window)
	fmt.printf("poster closed\n")
}

poster_handle_event :: proc(p: ^Poster, event: sdl.Event) {
	if event.type == .WINDOWEVENT {
		we := event.window
		if we.event == .CLOSE {
			p.kill = true
		}
	}
}
