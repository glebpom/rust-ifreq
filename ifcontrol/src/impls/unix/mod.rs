cfg_if! {
    if #[cfg(any(target_os = "linux",
                 target_os = "android",
                 target_os = "fuchsia"))] {
        mod notbsd;
        use self::notbsd::*;
    } else if #[cfg(any(target_os = "macos",
                        target_os = "ios",
                        target_os = "freebsd",
                        target_os = "dragonfly",
                        target_os = "openbsd",
                        target_os = "netbsd",
                        target_os = "bitrig"))] {
        mod bsd;
        use self::bsd::*;
    } else {
        // Unknown target_os
    }
}

use errors::{Error, ErrorKind, Result};
use ifstructs::ifreq;
use ifstructs::IfFlags;
use libc;
use nix;
use nix::sys::socket::{socket, AddressFamily, SockFlag, SockType};
use std::fs::File;
use std::os::unix::io::{AsRawFd, FromRawFd};

macro_rules! ti {
    ($e:expr) => {
        match $e {
            Ok(r) => Ok(r),
            Err(nix::Error::Sys(nix::errno::Errno::ENXIO)) => {
                Err(::errors::ErrorKind::IfaceNotFound.into())
            }
            Err(e) => Err(::errors::Error::from(e)),
        }
    };
}

pub fn new_control_socket() -> Result<File> {
    Ok(unsafe {
        File::from_raw_fd(socket(
            AddressFamily::Inet,
            SockType::Datagram,
            SockFlag::empty(),
            None,
        )?)
    })
}

pub fn get_iface_ifreq<F: AsRawFd>(ctl_fd: &F, ifname: &str) -> Result<ifreq> {
    let mut req = ifreq::from_name(ifname)?;
    ti!(unsafe { iface_get_flags(ctl_fd.as_raw_fd(), &mut req) })?;
    Ok(req)
}

pub fn is_up<F: AsRawFd>(ctl_fd: &F, ifname: &str) -> Result<bool> {
    let mut req = ifreq::from_name(ifname)?;
    ti!(unsafe { iface_get_flags(ctl_fd.as_raw_fd(), &mut req) })?;

    let mut flags = unsafe { req.get_flags() };

    Ok(flags.contains(IfFlags::IFF_UP) && flags.contains(IfFlags::IFF_RUNNING))
}

pub fn up<F: AsRawFd>(ctl_fd: &F, ifname: &str) -> Result<()> {
    if is_up(ctl_fd, ifname)? {
        return Ok(());
    }

    let mut req = ifreq::from_name(ifname)?;
    ti!(unsafe { iface_get_flags(ctl_fd.as_raw_fd(), &mut req) })?;

    unsafe { req.insert_flags(IfFlags::IFF_UP) };
    unsafe { req.insert_flags(IfFlags::IFF_RUNNING) };

    unsafe { iface_set_flags(ctl_fd.as_raw_fd(), &mut req) }?;

    Ok(())
}

pub fn down<F: AsRawFd>(ctl_fd: &F, ifname: &str) -> Result<()> {
    if !is_up(ctl_fd, ifname)? {
        return Ok(());
    }

    let fd = ctl_fd.as_raw_fd();

    let mut req = ifreq::from_name(ifname)?;
    ti!(unsafe { iface_get_flags(ctl_fd.as_raw_fd(), &mut req) })?;

    unsafe { req.remove_flags(IfFlags::IFF_UP) };
    unsafe { req.remove_flags(IfFlags::IFF_RUNNING) };

    unsafe { iface_set_flags(ctl_fd.as_raw_fd(), &mut req) }?;
    Ok(())
}

#[cfg(not(target_os = "android"))]
pub fn get_all_addresses() -> Result<nix::ifaddrs::InterfaceAddressIterator> {
    Ok(nix::ifaddrs::getifaddrs()?)
}
