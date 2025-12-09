%global srcname livereduce
%global summary Daemon for running live data reduction with systemd
# This only supports python3
%define release 1

Summary: %{summary}
Name: python-%{srcname}
Version: 1.17
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
Requires: systemd

%description
Daemon for running the algorithm StartLiveData

%{?python_provide:%python_provide python%{python3_pkgversion}-%{srcname}}

%package watchdog
Summary: Watchdog for restarting livereduce daemon
# may need to tweak the main package name as macros change
Requires:  python-%{srcname} = %{version}-%{release}

%description watchdog
Daemon for running the algorithm StartLiveData

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

%preun
%systemd_preun livereduce.service
%{__rm} -f /var/log/SNS_applications/livereduce.log*

%preun watchdog
%systemd_preun livereduce_watchdog.service
%{__rm} -f /var/log/SNS_applications/livereduce_watchdog.log*

%postun
%systemd_postun_with_restart livereduce.service

%postun watchdog
%systemd_postun_with_restart livereduce_watchdog.service

%files
%doc README.md
%{_bindir}/livereduce.py
%{_bindir}/livereduce.sh
%{_unitdir}/livereduce.service

%files watchdog
%{_bindir}/livereduce_watchdog.sh
%{_unitdir}/livereduce_watchdog.service
