module github.com/funwithactivity/funwithactivity/app-server

go 1.23

require (
	github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api v0.0.0
	github.com/google/uuid v1.6.0
	github.com/joho/godotenv v1.5.1
	github.com/stretchr/testify v1.9.0
	google.golang.org/grpc v1.60.0
)

require (
	github.com/davecgh/go-spew v1.1.1 // indirect
	github.com/golang/protobuf v1.5.3 // indirect
	github.com/pmezard/go-difflib v1.0.0 // indirect
	golang.org/x/net v0.16.0 // indirect
	golang.org/x/sys v0.13.0 // indirect
	golang.org/x/text v0.13.0 // indirect
	google.golang.org/genproto/googleapis/rpc v0.0.0-20231002182017-d307bd883b97 // indirect
	google.golang.org/protobuf v1.31.0 // indirect
	gopkg.in/yaml.v3 v3.0.1 // indirect
)

replace github.com/funwithactivity/funwithactivity/api/gen/go/funwithactivity/api => ../api/gen/go/funwithactivity/api
