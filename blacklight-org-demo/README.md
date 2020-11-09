# blacklight-org-demo

The plan is to dockerize blacklight.

## Steps

Starting from ubuntu, install the packages we need to build
ruby on rails.  So, ruby, curl, git, gcc, make, etc.
The list was discovered based on the needs of the things after.

We even need to add a new repository so we can get the latest yarn.

Then we create a user, become that user to create a local ruby environment.
With our local ruby and gem, we install the things blacklight needs.

Only then can we run rails to create our new search_app.

We have to update the .solr-wrapper.yml to point to our Solr
(hardcoded to my IP for now), and set the SOLR-URL to poitn at it.

And when we run rails, we want to bind to all IPs of the test server,
so we use the --binding parameter.

## Future Work

It runs, but its default search of the catalog is using fields
not in the OSTI data.  Perhaps rewrite the ruby to change the field names
or load the data into Solr with appropriate values in the desired fields.
