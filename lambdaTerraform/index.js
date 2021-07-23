console.log('starting function');

const AWS = require('aws-sdk');
const docClient = new AWS.DynamoDB.DocumentClient({region: process.env.AWS_DYNAMODB_REGION});
const sgMail = require("@sendgrid/mail");
sgMail.setApiKey(process.env.SENDGRID_API_KEY);

exports.handler = function(event, context, callback){

  const message = {
    to: event.mailaddress,
    from: process.env.SENDGRID_FROM_ADDRESS,
    templateId: process.env.SENDGRID_TEMPLATE_ID,
    dynamic_template_data: {
        first_name: event.firstname,
    },
  };
  sgMail.send(message);
    
    var params = {
        Item: {
        email: event.mailaddress,
        firstname: event.firstname
        },
        TableName:process.env.TABLE_NAME
    }
    
    docClient.put(params, function(err, data){
        if (err){
            callback(err, null);
        }else{
            callback(null,event.firstname);
        }
    });
}
