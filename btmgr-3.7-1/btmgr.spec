Summary: Smart Boot Manager is an OS independent boot manager.
Name: btmgr

%define version 3.7
%define prefix /usr

Version: %{version}
Release: 1
Group: Utilities
Copyright: GPL
Source: btmgr-%{version}-%{release}.tar.gz
URL: http://www.gnuchina.org/~suzhe/
Packager: James Su <suzhe@gnuchina.org>

%description
The main goals of SBM are to be absolutely OS independent, flexible
and full-featured. It has all of the features needed to boot a
variety of OSes from several kinds of media, while keeping its size no 
more than 30K bytes. In another words, SBM does NOT touch any of
your partitions, it totally fits into the first track (the hidden track) of
your hard disk! 
SBM now supports booting from floppy, hard disk and CD-ROM. 
There are plans to support ZIP and LS-120 in the near future.


%prep
%setup -n btmgr-%{version}-%{release}

%build
make

%install
make install PREFIX=$RPM_BUILD_ROOT/%{prefix} VERSION=3.7

%files
%{prefix}/sbin/sbminst
%{prefix}/share/btmgr
%{prefix}/share/doc/btmgr-%{version}
