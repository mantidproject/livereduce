# Container with systemd as PID 1 for exercising livereduce_filewatch.service against a real
# livereduce.service. Build from the repository root; see the `test-systemd` pixi task.
FROM registry.access.redhat.com/ubi9/ubi-init

USER root

RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm \
    && dnf install -y inotify-tools jq procps-ng python3 python-unversioned-command which \
    && dnf clean all

RUN groupadd -r users 2>/dev/null || true
RUN useradd -r -g users snsdata

# install the pieces under test the same way livereduce.spec does
COPY scripts/livereduce.sh scripts/livereduce_filewatch.sh /usr/bin/
COPY livereduce.service livereduce_filewatch.service /usr/lib/systemd/system/
RUN chmod 755 /usr/bin/livereduce.sh /usr/bin/livereduce_filewatch.sh \
    && mkdir -p /var/log/SNS_applications \
    && chown snsdata /var/log/SNS_applications \
    && chmod 1755 /var/log/SNS_applications

# stand-ins for mantid's livereduce.py and SNS's nsd-app-wrap, which aren't available here
COPY test/systemd/fake_livereduce.py /usr/bin/livereduce.py
COPY test/systemd/nsd-app-wrap.sh /usr/local/bin/
COPY test/systemd/check_restarts.sh /usr/local/bin/
# nsd-app-wrap.sh must be executable for livereduce.sh's `which` to find it
RUN chmod 755 /usr/local/bin/check_restarts.sh /usr/local/bin/nsd-app-wrap.sh

CMD ["/sbin/init"]
