# Claude Notes

High-quality GIF from video: `ffmpeg -i input.mov -vf "fps=30,scale=1600:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=256:reserve_transparent=0:stats_mode=diff[p];[s1][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" -loop 0 output.gif`
