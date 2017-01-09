%global srcname plotly
%global summary Python plotting library for collaborative, interactive, publication-quality graphs.
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
Version: 1.12.12
Release: %{release}%{?dist}
Source0: https://pypi.python.org/packages/ca/bc/229aba67f7a65f3fa7e30b77fc8dd42036e56388a108294ec7bcddfcaedc/plotly-1.12.12.tar.gz
License: MIT
Group: Development/Libraries
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-buildroot
Prefix: %{_prefix}
BuildArch: noarch
Vendor: Chris P <chris@plot.ly>
Url: https://plot.ly/python/

BuildRequires: python2-devel
BuildRequires: python-ipython
%if %{with_python3}
BuildRequires: python3-devel
BuildRequires: python3-ipython
%endif

%description
Plotly_ is an online collaborative data analysis and graphing tool. The
Python API allows you to access all of Plotly's functionality from Python.
Plotly figures are shared, tracked, and edited all online and the data is
always accessible from the graph.

That's it. Find out more, sign up, and start sharing by visiting us at
https://plot.ly.

This source rpm will generate both python2 and python3 libraries.


%package -n python2-%{srcname}
Summary:        %{summary}
Requires:      python
%if 0%{?rhel}
Requires: python-matplotlib
%else
Requires: python2-matplotlib
%endif
%{?python_provide:%python_provide python2-%{srcname}}

%description -n python2-%{srcname}
Plotly_ is an online collaborative data analysis and graphing tool. The
Python API allows you to access all of Plotly's functionality from Python.
Plotly figures are shared, tracked, and edited all online and the data is
always accessible from the graph.

That's it. Find out more, sign up, and start sharing by visiting us at
https://plot.ly.

%if %{with_python3}
%package -n python3-%{srcname}
Summary:        %{summary}
Requires:      python3
Requires: python3-matplotlib
%{?python_provide:%python_provide python3-%{srcname}}

%description -n python3-%{srcname}
Plotly_ is an online collaborative data analysis and graphing tool. The
Python API allows you to access all of Plotly's functionality from Python.
Plotly figures are shared, tracked, and edited all online and the data is
always accessible from the graph.

That's it. Find out more, sign up, and start sharing by visiting us at
https://plot.ly.
%endif

%prep
%setup -n %{srcname}-%{version} -n %{srcname}-%{version}

%build
%py2_build
%if %{with_python3}
%py3_build
%endif

%install
%py2_install
%if %{with_python3}
%py3_install
%endif

%check
%{__python2} setup.py test
%if %{with_python3}
%{__python3} setup.py test
%endif

%clean
rm -rf $RPM_BUILD_ROOT

%files -n python2-%{srcname}
%doc README.rst
%{python2_sitelib}/%{srcname}/*
%{python2_sitelib}/%{srcname}-%{version}-py2*.egg-info/*

%if %{with_python3}
%files -n python3-%{srcname}
%doc README.rst
%{python3_sitelib}/%{srcname}/*
%{python3_sitelib}/%{srcname}-%{version}-py3*.egg-info/*
%endif
