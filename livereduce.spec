%global srcname livereduce
%global summary Daemon for running live data reduction with systemd
# RHEL doesn't know about __python2
%{!?__python2: %define __python2 %{__python}}
%if 0%{?rhel}
  %define with_python3 0
%else
  %define with_python3 1
%endif

%define release 1

Summary: %{summary}
Name: python-%{srcname}
Version: 1.0
Release: %{release}%{?dist}
#Source0: https://pypi.python.org/packages/ca/bc/229aba67f7a65f3fa7e30b77fc8dd42036e56388a108294ec7bcddfcaedc/plotly-1.12.12.tar.gz
Source0: %{srcname}-%{version}.tar.gz
License: MIT
Group: Development/Libraries
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Prefix: %{_prefix}
BuildArch: noarch
Vendor: Pete Peterson
Url: https://github.com/mantidproject/livereduce

%description
There should be a meaninful description, but it is not needed quite yet.

Requires:      python

%{?python_provide:%python_provide python2-%{srcname}}

%prep
%setup -n %{srcname}-%{version} -n %{srcname}-%{version}

%build
%py2_build

%install
%py2_install

%check
%{__python2} setup.py test

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
%{python2_sitelib}/*
%{_bindir}/reduce_live.py
%{_prefix}/lib/systemd/system/livereduce.service
