import os

AWS_PATH = "aws"
os.system(AWS_PATH+" s3 sync s3://chronos-baselines/ .")
os.system("chmod +x binaries/*")
