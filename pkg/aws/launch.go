package aws

import (
    "fmt"

    "github.com/aws/aws-sdk-go/aws"
    "github.com/aws/aws-sdk-go/aws/session"
    "github.com/aws/aws-sdk-go/service/ec2"
	
	"github.com/mdshuai/onion/pkg/util/rand"
)

type AwsManager struct {
	AwsAccessKeyId string
	AwsSecretAccessKey string
	MasterNum int
	NodeNumber int		
	MasterPrefix string
	NodePrefix string
	Production string //support only: k8s and openshift
}

func NewAwsManager(production string) *AwsManager {
	prefix := rand.String(5)
	masterPrefix := prefix
	nodePrefix := prefix
	if strings.EqualFold("openshift", production) {
		masterPrefix = fmt.Sprintf("%s-%s", masterPrefix, "openshift-master")
		nodePrefix = fmt.Sprintf("%s-%s", nodePrefix, "openshift-node")
	} else if strings.EqualFold("kubernetes", production){
		masterPrefix = fmt.Sprintf("%s-%s", masterPrefix, "k8s-master")
		nodePrefix = fmt.Sprintf("%s-%s", nodePrefix, "k8s-node")
	}
	return &AwsManager{
		AwsAccessKeyId: 	""
		AwsSecretAccessKey: ""
		MasterNum:			1
		NodeNumber:			2
		MasterPrefix:		masterPrefix
		NodePrefix:			nodePrefix
		Production:			production
	}
}

// Create a aws instance
func (m *AwsManager) LaunchInstance(name string) {
    // Create an EC2 service object in the "us-west-2" region
    // Note that you can also configure your region globally by
    // exporting the AWS_REGION environment variable
    svc := ec2.New(session.New(), &aws.Config{Region: aws.String("us-west-2")})

    // Call the DescribeInstances Operation
    resp, err := svc.DescribeInstances(nil)
    if err != nil {
        panic(err)
    }

    // resp has all of the response data, pull out instance IDs:
    fmt.Println("> Number of reservation sets: ", len(resp.Reservations))
    for idx, res := range resp.Reservations {
        fmt.Println("  > Number of instances: ", len(res.Instances))
        for _, inst := range resp.Reservations[idx].Instances {
            fmt.Println("    - Instance ID: ", *inst.InstanceId)
        }
    }
}

//Terminate a ec2 instance
func (m *AwsManager) TerminateInstance() {
	//TODO
}

//Run will start a job to create all the instance
func (m *AwsManager) Run() {
	//TODO
	for i := 1; i <= m.MasterNum; i++ {
		LaunchInstance(m.)
	}
	for i := 1; i <= m.NodeNum; i++ {
		LaunchInstance()
	}
}
