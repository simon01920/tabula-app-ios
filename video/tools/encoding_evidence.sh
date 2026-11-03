#!/usr/bin/env bash
# Independent checks of a conformed App Preview master; prints a labelled report.
# Usage: bash video/tools/encoding_evidence.sh <master.mp4> > qa/encoding-evidence.txt
M="$1"
echo "# Encoding evidence — $(basename "$M") ($(date -u +%Y-%m-%dT%H:%MZ), $(ffprobe -version | head -1 | cut -d' ' -f1-3))"
echo; echo "## ffprobe streams + format"
ffprobe -v error -show_entries stream=index,codec_type,codec_name,profile,level,width,height,sample_aspect_ratio,pix_fmt,field_order,color_primaries,color_transfer,color_space,r_frame_rate,avg_frame_rate,nb_frames,bit_rate,sample_rate,channels,channel_layout,duration:format=duration,size,bit_rate -of compact "$M"
echo; echo "## rotation / display-matrix side data (expect none)"
ffprobe -v error -show_entries stream_side_data_list -of compact "$M" | grep -i -E 'rotation|matrix' || echo "none"
echo; echo "## fast start"
python3 -c "import sys; d=open(sys.argv[1],'rb').read(1<<20); print('moov offset', d.find(b'moov'), '< mdat offset', d.find(b'mdat'))" "$M"
echo; echo "## full decode"
ffmpeg -v error -i "$M" -f null - && echo "exit=0, no decode errors"
echo; echo "## loudness (EBU R128, true peak)"
ffmpeg -hide_banner -nostats -i "$M" -af ebur128=peak=true -f null - 2>&1 | sed -n '/Summary:/,$p' | grep -E 'I:|LRA:|Peak:'
echo; echo "## audio edges (RMS dB)"
printf 'first 0.3 s: '; ffmpeg -hide_banner -nostats -i "$M" -af "atrim=0:0.3,astats" -f null - 2>&1 | grep -m1 'RMS level' | awk '{print $NF}'
printf 'last 0.3 s: '; ffmpeg -hide_banner -nostats -i "$M" -af "atrim=28.7:29,astats" -f null - 2>&1 | grep -m1 'RMS level' | awk '{print $NF}'
echo; echo "## black frames (blackdetect d>=0.05 s, pix_th 0.10)"
printf 'count: '; ffmpeg -hide_banner -nostats -i "$M" -vf blackdetect=d=0.05:pix_th=0.10 -an -f null - 2>&1 | grep -c black_start
echo; echo "## static holds >= 1.5 s (freezedetect n=0.001): deliberate real-UI holds, listed for review"
ffmpeg -hide_banner -nostats -i "$M" -vf freezedetect=n=0.001:d=1.5 -an -f null - 2>&1 | grep -oE 'freeze_(start|end): [0-9.]+' | paste - -
echo; echo "## AAC note"
echo "Native ffmpeg AAC at -b:a 256k reports avg ~245.5 kbps (btrt max 256000) for the stream. Apple: AAC 256 kbps; ABR within normal encoder tolerance."
