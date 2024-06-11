# Callisto Editor

Command line (for now) tools for creating assets compatible with
the Callisto game engine.

### Portability

Many of the tools in this program are bindings of C static libraries.
I am using Windows, but for the editor to be cross platform the following third-party libraries
require build scripts:


| Library | Windows | Linux | Mac (x86) | Mac (arm) |
| ------- | ------- | ----- | --------- | --------- |
| MikkTSpace        | ➕ | ➕ | ➕ | ➕ |
| Spirv-Reflect     | ➕ | ❌ | ❌ | ❌ |
| glsl-lang         | ?  | ❌ | ❌ | ❌ |
