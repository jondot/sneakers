# Sneakers Change Log

## Changes Between 2.6.0 and 2.7.0

This release requires Ruby 2.2 and has **breaking API changes**
around custom error handlers.

### Use Provided Connections in WorkerGroup

It is now possible to use a custom connection instance in worker groups.

Contributed by @pomnikita.

GitHub issue: [#322](https://github.com/jondot/sneakers/pull/322)


### Worker Context Available to Worker Instances

Contributed by Jason Lombardozzi.

GitHub issue: [#307](https://github.com/jondot/sneakers/pull/307)


### Ruby 2.2 Requirement

Sneakers now [requires Ruby 2.2](https://github.com/jondot/sneakers/commit/f33246a1bd3b5fe53ee662253dc5bac7864eec97).


### Bunny 2.9.x

Bunny was [upgraded](https://github.com/jondot/sneakers/commit/c7fb0bd23280082e43065d7199668486db005c13) to 2.9.x.



### Server Engine 2.0.5

Server Engine dependency was [upgraded to 2.0.5](https://github.com/jondot/sneakers/commit/3f60fd5e88822169fb04088f0ce5d2f94f803339).


### Refactored Publisher Connection

Contributed by Christoph Wagner.

GitHub issue: [#325](https://github.com/jondot/sneakers/pull/325)


### New Relic Reporter Migrated to the Modern API

Contributed by @adamors.

GitHub issue: [#324](https://github.com/jondot/sneakers/pull/324)


### Configuration Logged at Debug Level

To avoid potentially leaking credentials in the log.

Contributed by Kimmo Lehto.

GitHub issue: [#301](https://github.com/jondot/sneakers/pull/301).


### Comment Corrections

Contributed by Andrew Babichev

GitHub issue: [#346](https://github.com/jondot/sneakers/pull/346)
