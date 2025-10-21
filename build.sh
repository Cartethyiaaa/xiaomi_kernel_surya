#!/bin/bash
#
# Compile script for Lucifer kernel
# Mahirooo | HiraTeam.

SECONDS=0 # builtin bash timer
ZIPNAME="Lucifer-surya-$(date '+%Y%m%d-%H%M').zip"
LOCAL_DIR="$(pwd)"
TC_DIR="$(pwd)/tc/clang-20"
AK3_DIR="$(pwd)/android/AnyKernel3"
DEFCONFIG="surya_defconfig"

if test -z "$(git rev-parse --show-cdup 2>/dev/null)" &&
   head=$(git rev-parse --verify HEAD 2>/dev/null); then
	ZIPNAME="${ZIPNAME::-4}-$(echo $head | cut -c1-8).zip"
fi

export PATH="$TC_DIR/bin:$PATH"

sync_repo() {
    local dir=$1
    local repo_url=$2
    local branch=$3
	local update=$4

    if [ -d "$dir" ]; then
        if $update; then
            git -C "$dir" fetch origin --quiet

            LOCAL_COMMIT=$(git -C "$dir" rev-parse HEAD)
            REMOTE_COMMIT=$(git -C "$dir" rev-parse "origin/$branch")

            if [ "$LOCAL_COMMIT" != "$REMOTE_COMMIT" ]; then
                git -C "$dir" reset --quiet --hard "origin/$branch"
                LATEST_COMMIT=$(git -C "$dir" log -1 --oneline)
                echo -e "Updated $repo_url to: $LATEST_COMMIT\n" | tee -a "$dir/updates.txt"
            else
                echo "No changes found for $repo_url. Skipping update."
            fi
        fi
    else
        echo "Cloning $repo_url to $dir..."
        if ! git clone --quiet --depth=1 -b "$branch" "$repo_url" "$dir"; then
            echo "Cloning failed! Aborting..."
            exit 1
        fi
    fi
}

if [[ $1 = "-u" || $1 = "--update" ]]; then
    sync_repo $TC_DIR "https://bitbucket.org/rdxzv/clang-standalone.git" "20" true
	exit
else
    sync_repo $TC_DIR "https://bitbucket.org/rdxzv/clang-standalone.git" "20" false
fi

if [[ $1 = "-r" || $1 = "--regen" ]]; then
	make $DEFCONFIG savedefconfig
	cp out/defconfig arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated defconfig at $DEFCONFIG"
	exit
fi

if [[ $1 = "-rf" || $1 = "--regen-full" ]]; then
	make $DEFCONFIG
	cp out/.config arch/arm64/configs/$DEFCONFIG
	echo -e "\nSuccessfully regenerated full defconfig at $DEFCONFIG"
	exit
fi

CLEAN_BUILD=false
ENABLE_KSU=false

for arg in "$@"; do
	case $arg in
		-c|--clean)
			CLEAN_BUILD=true
			;;
		-s|--su)
			ENABLE_KSU=true
			ZIPNAME="${ZIPNAME/Lucifer-surya/Lucifer-KSU}"
			;;
		*)
			echo "Unknown argument: $arg"
			exit 1
			;;
	esac
done

if $CLEAN_BUILD; then
	echo "Cleaning output directory..."
	rm -rf out
fi

if $ENABLE_KSU; then
	echo "Building with KSU support..."
	KSU_DEFCONFIG="ksu_${DEFCONFIG}"
	KSU_DEFCONFIG_PATH="arch/arm64/configs/${KSU_DEFCONFIG}"
	cp arch/arm64/configs/$DEFCONFIG $KSU_DEFCONFIG_PATH
	sed -i 's/# CONFIG_KSU is not set/CONFIG_KSU=y/g' $KSU_DEFCONFIG_PATH
	trap '[[ -f $KSU_DEFCONFIG_PATH ]] && rm -f $KSU_DEFCONFIG_PATH' EXIT
fi

echo -e "\nStarting compilation...\n"
if $ENABLE_KSU; then
	make $KSU_DEFCONFIG
else
	make $DEFCONFIG
fi
make -j$(nproc --all) LLVM=1 Image.gz dtb.img dtbo.img 2> >(tee log.txt >&2) || exit $?

if [ -f "out/arch/arm64/boot/Image.gz" ] && [ -f "out/arch/arm64/boot/dtbo.img" ]; then
echo -e "\nKernel compiled succesfully! Zipping up...\n"
if [ -d "$AK3_DIR" ]; then
cp -r $AK3_DIR AnyKernel3
elif ! git clone -q https://github.com/Cartethyiaaa/AnyKernel3.git; then
echo -e "\nAnyKernel3 repo not found locally and cloning failed! Aborting..."
exit 1
fi
cp out/arch/arm64/boot/Image.gz AnyKernel3
cp out/arch/arm64/boot/dtbo.img AnyKernel3
cp out/arch/arm64/boot/dtb.img AnyKernel3

rm -f *zip
cd AnyKernel3
git checkout Lucifer &> /dev/null
zip -r9 "../$ZIPNAME" * -x .git modules\* patch\* ramdisk\* README.md *placeholder
fi
cd ..
rm -rf AnyKernel3
rm -rf out/arch/arm64/boot
echo -e "======================================="
echo -e "------------Happy Flashing-------------"
echo -e "======================================="
echo -e "Completed in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "Zip: $ZIPNAME"
echo "Move Zip into Home Directory"
echo "Upload Zip to Pixeldrain"
curl -T ${LOCAL_DIR}/*.zip -u :bb2513da-caec-4d8c-9b95-84f05c8dd743 https://pixeldrain.com/api/file/
echo "DONE ALL"
echo -e "======================================="