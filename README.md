# Anycast Service Discovery with Docker

This service monitors the status of Docker containers and advertises healthy
service addresses in the route table.

Containers subscribe themselves to the service via the label `anycast.address`
in their metadata. The value of this label is the address to advertise when
the health check passes. When this service discovers a container with the
`anycast.address` label, it creates a tuntap interface and assigns it this
address. When the container reports healthy, the service will enable this
interface. When it reports unhealthy or stops, this interface is disabled. This
works in conjunction with a routing daemon on the host and
`redistribute connected` rule to advertise the address only when the container
is healthy.

## Prerequistes

These are assumed to already be installed:

* A routing daemon like Quagga configured with `redistribute connected`
* Docker CE
* docker-compose

## Usage

Check out `docker-compose.yml` for an example of how to deploy an anycast
service with this tool.

In the `helloworld` service example, the labels section is what subscribes
`helloworld` to the anycast service discovery tool.

```
labels:
  anycast.address: "192.0.2.1"
```

Once healthy, the discovery tool will advertise 192.0.2.1.

You also need to bind the container to this address. There are two ways to do
this. The easiest way is to bind to everything (0.0.0.0), like this:

```
ports:
 - "80:80"
```

In this case, you can start everything the typical way:

```
docker-compose up -d
```

You can also bind to the anycast address specifically:

```
ports:
 - "192.0.2.1:80:80"
```

**Note:** When binding to the anycast address, the services must be created and
launched in a particular order so that the address is bound on the host before
the container is started.

```
docker-compose up --no-start
docker-compose up -d discovery
docker-compose up -d
```

This works by first creating all the containers. Then the discovery service is
started, creates interfaces, and binds addresses for containers it finds. Then
the rest of the services will be able to bind to their addresses and start.
