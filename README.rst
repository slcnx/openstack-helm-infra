====================
Openstack-Helm-Infra
====================

由于我的系统是 CentOS 7.6.1810
20C 32G
```bash
export PodNET=10.10.0.0/16 # flannel/calico
export ServiceNet=10.20.0.0/16 # service
export localNet=192.168.0.0/24
```

需要修改下`tools/gate/deploy-k8s.sh` 文件中的服务名


Mission
-------

The goal of OpenStack-Helm-Infra is to provide charts for services or
integration of third-party solutions that are required to run OpenStack-Helm.

For more information, please refer to the OpenStack-Helm repository_.

.. _repository: https://github.com/openstack/openstack-helm

Communication
-------------

* Join us on `IRC <irc://chat.oftc.net/openstack-helm>`_:
  #openstack-helm on oftc
* Community `IRC Meetings
  <http://eavesdrop.openstack.org/#OpenStack-Helm_Team_Meeting>`_:
  [Every Tuesday @ 3PM UTC], #openstack-meeting-alt on oftc
* Meeting Agenda Items: `Agenda
  <https://etherpad.openstack.org/p/openstack-helm-meeting-agenda>`_
* Join us on `Slack <https://kubernetes.slack.com/messages/C3WERB7DE/>`_
  - #openstack-helm

Contributing
------------

We welcome contributions. Check out `this <CONTRIBUTING.rst>`_ document if
you would like to get involved.
