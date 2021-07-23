# AWS Serverless E-Mail API
A Terraform script that creates a serverless static website, an API, a Lambda function, and DynamoDB table for the purpose of creating an serverless web-form that can send personalized e-mails to website visitors. This is a personal project to learn more about Terraform, Serverless Tools in AWS, and API's. A demo of this website can be found at [Serverless E-Mail Demo](https://serverless.eshaanm.com)
# Design
![AWS Project Diagram](https://disney.eshaanm.com/graph2.png)
1. Website visitors use Route 53 DNS to access a CloudFront Distribution associated with an S3 Bucket
2.  Once the website is loaded, Users fill out a form which is used to make a POST request to an API Gateway REST API
3. The REST API triggers a Lambda function that stores the user data in a DynamoDB table and utilizes SendGrid API's to send an e-mail.

**Features**

 - One-click solution to create a  website, Lambda function, and API
 - Serverless architecture with zero maintenance and infinite scalability
 - IAM roles follow the Principle of Least Privilege by only allowing access to specific resources
 - Lambda function written in Node.js 

**Assumptions:**

 - Public Hosted Zone for Root Domain Name has been configured in Route53
 - AWS account has the necessary IAM privileges to provision resources
 - Terraform is installed correctly


## How to run 

1. Download the repository to your local machine with the following code.

    `git clone https://github.com/eshaanm25/serverless-emailer`
    
2. Fill out the `terraform.tfvars` file with the required environment variables. Variable descriptions can also be found in `variables.tf`

|       Variable         |Description                          |Example                         |
|----------------|-------------------------------|-----------------------------|
|aws-region|Region in which resources will be provisioned            |us-east-1            |
|access-key          |[Access key for AWS account](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html)             |AKSJKD34KHWWFW7OWP            |
|secret-key          |[Secret key from AWS account](https://docs.aws.amazon.com/general/latest/gr/aws-sec-cred-types.html)||
|sendgrid-api-key          |[API Key for SendGrid E-Mail](https://docs.sendgrid.com/for-developers/sending-email/api-getting-started#prerequisites-for-sending-your-first-email-with-the-sendgrid-api) |SG.XXXXX|
|sendgrid-template-id          |[SendGrid E-Mail Template Identifier](https://docs.sendgrid.com/ui/sending-email/how-to-send-an-email-with-dynamic-transactional-templates) |d-XXXXX|
|redirect-link          |Website that users will be redirected to once the form is completed|https://eshaanm.com|
|from-address        |E-Mail address that the SendGrid will send from|hello@eshaanm.com|
|site-domain       |Root domain that will be hosting static website|eshaanm.com|
|site-redirect       |Website that will be redirected to `site-domain`|www.eshaanm.com|
|tags|Tags that provisioned resources will have|{"Project" = "TerraForm"}|

3. Navigate to the repository directory and initialize Terraform by running `terraform init`
4. Execute the actions proposed in a Terraform plan by running `terraform apply`


