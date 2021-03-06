#!/bin/bash

dir=$1

if [ "$dir" = "" ]; then
	echo
	echo "Please provide a working directory"
	exit 1
fi

interval="90"
format="png"

function mplayerInfo
{
	mplayer -nosound -vo null -ss 03:00:00 -really-quiet -identify $1 2>&1
}

function parseHMS
{
	local hour=$(echo $1 | cut -d. -f1 | cut -d: -f1)
	local minute=$(echo $1 | cut -d. -f1 | cut -d: -f2)
	local second=$(echo $1 | cut -d. -f1 | cut -d: -f3)
	local frame=$(echo $1 | cut -d. -f2)
	echo "( $hour * 3600 ) + ( $minute * 60 ) + $second"  | bc -l
}

function getAnamorphicResolution
{
	local file=$1
	local width=$(mplayerInfo $file | grep ID_VIDEO_WIDTH | cut -d= -f2)
	local height=$(mplayerInfo $file | grep ID_VIDEO_HEIGHT | cut -d= -f2)
	local aspect=$(mplayerInfo $file | grep ID_VIDEO_ASPECT | cut -d= -f2)
	if [ $(echo $aspect | cut -d. -f1) != 0 ]; then
		local factor=$(echo "scale=5; $aspect / ( $width / $height )" | bc -l)
		local realWidth=$(echo $(echo "scale=2; $width*$factor" | bc -l) | cut -d. -f1)
		echo "${realWidth}x${height}"
	else 
		echo ""
	fi
}

function getDuration
{
	local file=$1
	parseHMS $(ffmpeg -i $file 2>&1 | grep Duration | awk '{print $2}' | sed s/,//)
}

function extract
{
	local i=$1
	local file=$2
	local destination="$(echo ${dir}still/$(echo $(basename $file) | sed s/\.mp4//) | sed s/\\/\\.//g)/origin"
	mkdir -p $destination
	ffmpeg -ss $i -i $file -an -vframes 1 $destination/$i.$format 2>/dev/null > /dev/null
	return $?
}

function process
{
	local foo=$1
	local dir=$2

        # Get film informations
        local duration=$(getDuration $dir/$foo)
        local resolution=$(getAnamorphicResolution $dir/$foo)

        echo "$foo ($duration sec.)"
        if [ "$resolution" != "" ]; then
                echo -e "\n\t[R] Anamorphism Support Enable ($resolution)"
        fi

        # Extract still
        echo -en "\t[E] "

	i="0"
        while [ $i -lt $duration ]; do
                extract $i $dir/$foo
                echo -n .
                i=$(($i + $interval))
        done

        local source="$(echo $dir/still/$(echo $foo | sed s/\.mp4//) | sed s/\\/\\.//g)/origin"

        # Anamorphism
        if [ "$resolution" != "" ]; then
                echo -en "\n\t[R] Anamorphism Support"
                gm mogrify -resize $resolution! +profile "*" $source/*.$format
        fi

        # Thumbs
        echo -e "\n\t[R] Generate thumbnails"
        thumbs="$(echo $dir/still/$(echo $foo | sed s/\.mp4//) | sed s/\\/\\.//g)/thumbs"
        mkdir -p $thumbs
        cp $source/* $thumbs/
        gm mogrify -resize 160x90 +profile "*" $thumbs/*.$format

	return 0
}

if [ -f $dir ]; then
	echo
	echo "Handle one file ..."
	
	foo=$(basename $dir)
	dir=$(echo $dir | sed s/$foo//)
	
	mkdir -p $dir/still
	
	process $foo $dir 
			
	exit 0
fi

mkdir -p $dir/still

for foo in $(ls $dir/*.mp4 2> /dev/null); do
	foo=$(basename $foo)
	echo
	i="0"
	
	# Check if film has change
	sumfile=${dir}.$(echo $foo | sed s/\.mp4//).md5
	if [ ! -f $sumfile ]; then
		md5 ${dir}${foo} | cut -d= -f2 | awk '{print $1}' > $sumfile
		newsum=$(cat $sumfile)
	else
		oldsum=$(cat $sumfile)
		newsum=$(md5 ${dir}${foo} | cut -d= -f2 | awk '{print $1}')
	fi
	
	if [ "$oldsum" = "$newsum" ] && [ -d ${dir}still/$(echo $foo | sed s/\.mp4//) ]; then
		echo "Skip $foo ..."
	else
		process $foo $dir
	echo
	fi
done

if [ $? = 0 ]; then
	echo
	echo "Movie/Directory not found, bye ..."
	echo
	exit 1
fi

exit 0
