# Paired AstrologyKit migration

`astrologykit-accuracy.patch` contains AstrologyKit commit
`92e7a773d1107a08efb3404d906b0323aef2f985`, based on
`85f2d440f231902581dd40726e19072c6fe832a9`. Apply it with `git am` in a clean
AstrologyKit checkout based on that revision, or use the prepared local branch
`astronomy-accuracy-integration` in `.context/AstrologyKit-migration`.

The manifest pins AstronomyKit source commit
`c68b96cb87b20a49697af133921b8ad55b7e6ad0` using the public repository URL.
The source commit must be published before external consumers can resolve it.
The local test used a gitignored bare mirror to resolve the exact commit;
no local path or mirror configuration is included in this patch.

See [the production acceptance record](../../PRODUCTION-INTEGRATION.md) for
validation and the release work that remains. This patch does not close #369.
