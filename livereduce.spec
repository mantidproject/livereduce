%global srcname livereduce
%global summary Daemon for running live data reduction with systemd
# This only supports python3
%define release 1
# give default version for linting
%if "%{?version}" == ""
%define version 0.0
%endif

Summary: %{summary}
Name: python-%{srcname}
Version: %{version}
Release: %{release}%{?dist}
Source0: %{srcname}-%{version}.tar.gz
License: MIT
Group: Development/Libraries
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Prefix: %{_prefix}
BuildArch: noarch
Vendor: Pete Peterson
Url: https://github.com/mantidproject/livereduce

BuildRequires: python%{python3_pkgversion}
BuildRequires: systemd-rpm-macros

Requires: python%{python3_pkgversion}
Requires: jq
Requires: nsd-app-wrap
Requires: polkit
Requires: systemd

%description
Daemon for running the algorithm StartLiveData

%{?python_provide:%python_provide python%{python3_pkgversion}-%{srcname}}

%package watchdog
Summary: Watchdog for restarting livereduce daemon
# may need to tweak the main package name as macros change
Requires:  python-%{srcname} = %{version}-%{release}

%description watchdog
Daemon that monitors the livereduce log file and restarts service livereduce if necessary

%package filewatch
Summary: File watcher for restarting livereduce daemon on configuration/script changes
# may need to tweak the main package name as macros change
Requires:  python-%{srcname} = %{version}-%{release}
Requires:  inotify-tools

%description filewatch
Daemon that watches /etc/livereduce.conf and the processing/post-processing scripts, and
restarts service livereduce whenever any of them are created, modified, or deleted. livereduce
itself only reads these files at startup (see "Remove pyinotify" mantidproject/livereduce#74).

%prep
%setup -q -n %{srcname}-%{version}

%build
# no build step

%install
%{__rm} -rf $RPM_BUILD_ROOT
# put things in the bin directory
%{__mkdir} -p %{buildroot}%{_bindir}/
%{__install} -m 644 scripts/livereduce.py %{buildroot}%{_bindir}/
%{__install} -m 755 scripts/livereduce.sh %{buildroot}%{_bindir}/
%{__mkdir} -p %{buildroot}%{_unitdir}/
%{__install} -m 644 livereduce.service %{buildroot}%{_unitdir}/
# watchdog service
%{__install} -m 755 scripts/livereduce_watchdog.sh %{buildroot}%{_bindir}/
%{__install} -m 644 livereduce_watchdog.service %{buildroot}%{_unitdir}/
%{__mkdir} -p %{buildroot}%{_sysconfdir}/polkit-1/rules.d/
%{__install} -m 644 50-snsdata-livereduce.rules %{buildroot}%{_sysconfdir}/polkit-1/rules.d/
# filewatch service
%{__install} -m 755 scripts/livereduce_filewatch.sh %{buildroot}%{_bindir}/
%{__install} -m 644 livereduce_filewatch.service %{buildroot}%{_unitdir}/

%check
# no test step

%clean
%{__rm} -rf $RPM_BUILD_ROOT

%pre
# Check if required users exist; fail install if snsdata missing
%{__id} snsdata > /dev/null 2>&1 || { echo "Error: snsdata user not found. Please create it before installing this package."; exit 1; }

%post
%systemd_post livereduce.service
%{__mkdir} -p /var/log/SNS_applications/
%{__chown} snsdata /var/log/SNS_applications/
%{__chmod} 1755 /var/log/SNS_applications/

%post watchdog
%systemd_post livereduce_watchdog.service

%post filewatch
%systemd_post livereduce_filewatch.service

%preun
%systemd_preun livereduce.service
%{__rm} -f /var/log/SNS_applications/livereduce.log*

%preun watchdog
%systemd_preun livereduce_watchdog.service
%{__rm} -f /var/log/SNS_applications/livereduce_watchdog.log*

%preun filewatch
%systemd_preun livereduce_filewatch.service
%{__rm} -f /var/log/SNS_applications/livereduce_filewatch.log*

%postun
%systemd_postun_with_restart livereduce.service

%postun watchdog
%systemd_postun_with_restart livereduce_watchdog.service

%postun filewatch
%systemd_postun_with_restart livereduce_filewatch.service

%files
%doc README.md
%{_bindir}/livereduce.py
%{_bindir}/livereduce.sh
%{_unitdir}/livereduce.service

%files watchdog
%{_bindir}/livereduce_watchdog.sh
%{_unitdir}/livereduce_watchdog.service
%config(noreplace) %{_sysconfdir}/polkit-1/rules.d/50-snsdata-livereduce.rules

%files filewatch
%{_bindir}/livereduce_filewatch.sh
%{_unitdir}/livereduce_filewatch.service
