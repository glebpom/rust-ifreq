#!/bin/sh

# Builds and runs tests for a particular target passed as an argument to this
# script.

set -ex

TARGET=$1

# If we're going to run tests inside of a qemu image, then we don't need any of
# the scripts below. Instead, download the image, prepare a filesystem which has
# the current state of this repository, and then run the image.
#
# It's assume that all images, when run with two disks, will run the `run.sh`
# script from the second which we place inside.
if [ "$QEMU" != "" ]; then
  tmpdir=/tmp/qemu-img-creation
  mkdir -p $tmpdir

  if [ -z "${QEMU#*.gz}" ]; then
    # image is .gz : download and uncompress it
    qemufile=$(echo ${QEMU%.gz} | sed 's/\//__/g')
    if [ ! -f $tmpdir/$qemufile ]; then
      curl https://s3-us-west-1.amazonaws.com/rust-lang-ci2/libc/$QEMU | \
        gunzip -d > $tmpdir/$qemufile
    fi
  elif [ -z "${QEMU#*.xz}" ]; then
    # image is .xz : download and uncompress it
    qemufile=$(echo ${QEMU%.xz} | sed 's/\//__/g')
    if [ ! -f $tmpdir/$qemufile ]; then
      curl https://s3-us-west-1.amazonaws.com/rust-lang-ci2/libc/$QEMU | \
        unxz > $tmpdir/$qemufile
    fi
  else
    # plain qcow2 image: just download it
    qemufile=$(echo ${QEMU} | sed 's/\//__/g')
    if [ ! -f $tmpdir/$qemufile ]; then
      curl https://s3-us-west-1.amazonaws.com/rust-lang-ci2/libc/$QEMU \
        > $tmpdir/$qemufile
    fi
  fi

  # Create a mount a fresh new filesystem image that we'll later pass to QEMU.
  # This will have a `run.sh` script will which use the artifacts inside to run
  # on the host.
  rm -f $tmpdir/ifstructs-test.img
  mkdir $tmpdir/mount

  # Do the standard rigamarole of cross-compiling an executable and then the
  # script to run just executes the binary.
  cargo build \
    --tests \
    --target $TARGET
  rm $CARGO_TARGET_DIR/debug/ifstructs-*.d
  cp $CARGO_TARGET_DIR/debug/ifstructs-* $tmpdir/mount/ifstructs-test
  echo 'exec $1/ifstructs-test' > $tmpdir/mount/run.sh

  du -sh $tmpdir/mount
  genext2fs \
      --root $tmpdir/mount \
      --size-in-blocks 100000 \
      $tmpdir/ifstructs-test.img

  # Pass -snapshot to prevent tampering with the disk images, this helps when
  # running this script in development. The two drives are then passed next,
  # first is the OS and second is the one we just made. Next the network is
  # configured to work (I'm not entirely sure how), and then finally we turn off
  # graphics and redirect the serial console output to out.log.
  qemu-system-x86_64 \
    -m 1024 \
    -snapshot \
    -drive if=virtio,file=$tmpdir/$qemufile \
    -drive if=virtio,file=$tmpdir/ifstructs-test.img \
    -net nic,model=virtio \
    -net user \
    -nographic \
    -vga none 2>&1 | tee $CARGO_TARGET_DIR/out.log
  exec grep "^PASSED .* tests" $CARGO_TARGET_DIR/out.log
fi

# FIXME: x86_64-unknown-linux-gnux32 fail to compile without --release
# See https://github.com/rust-lang/rust/issues/45417
opt=
if [ "$TARGET" = "x86_64-unknown-linux-gnux32" ]; then
  opt="--release"
fi

# Building with --no-default-features is currently broken on rumprun because we
# need cfg(target_vendor), which is currently unstable.
if [ "$TARGET" != "x86_64-rumprun-netbsd" ]; then
  cargo test $opt --no-default-features --target $TARGET
fi

exec cargo test $opt --target $TARGET
