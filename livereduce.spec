%global srcname livereduce
%global summary Daemon for running live data reduction with systemd
# This only supports python3
%define release 1

Summary: %{summary}
Name: python-%{srcname}
Version: 1.9
Release: %{release}%{?dist}
Source0: %{srcname}-%{version}.tar.gz
License: MIT
Group: Development/Libraries
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Prefix: %{_prefix}
BuildArch: noarch
Vendor: Pete Peterson
Url: https://github.com/mantidproject/livereduce

BuildRequires: python%{python3_pkgversion} python%{python3_pkgversion}-setuptools

Requires: python%{python3_pkgversion}
Requires: jq
Requires: nsd-app-wrap

%description
There should be a meaningful description, but it is not needed quite yet.

%{?python_provide:%python_provide python-%{srcname}}

%prep
%setup -n %{srcname}-%{version} -n %{srcname}-%{version}

%build
%py3_build

%install
%py3_install

%check
%{__python3} setup.py test

%clean
rm -rf $RPM_BUILD_ROOT

%post
mkdir -p /var/log/SNS_applications/
chown snsdata /var/log/SNS_applications/
chmod 1755 /var/log/SNS_applications/

%preun
rm -f /var/log/SNS_applications/livereduce.log*

%files
%doc README.md
%{python3_sitelib}/*
%{_bindir}/livereduce.py
%{_bindir}/livereduce.sh
%{_prefix}/lib/systemd/system/livereduce.service
