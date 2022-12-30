#!/bin/bash

#设定软件安装目录
INSTALL_DIR=/opt/software/
#指定jdk下载网址
JDKLINK='https://download.oracle.com/otn-pub/java/jdk/8u191-b12/2787e4a523244c269598db4e85c51e0c/jdk-8u191-linux-x64.tar.gz'
#指定hadoop下载网址
HADOOPLINK='https://archive.apache.org/dist/hadoop/common/hadoop-2.6.5/hadoop-2.6.5.tar.gz'
#获取本地ip地址
#方法一：ipa的结果取出所有含有inet的行，选择其中第二行，用空格切分取第二个元素，/切分取第一个元素即为ip地址
#echo `ip a|awk '/inet /' |sed -n '2p' |awk -F' ' '{print $2}' |awk -F'/' '{print $1}'`
#方法二
local_IP=$(ip a | grep ens33 | awk '$1~/^inet.*/{print $2}' | awk -F '/' '{print $1}')
#用于存储集群节点ip地址
ip_arrays=()

#检查wget是否正常
install_wget(){
        echo '初始化安装环境....'
        wget 2>/dev/null
        if [ $? -ne 1 ]; then
                echo '开始下载wget'
                yum -y install wget
        else
        echo 'wget一切正常'
        fi
}

#优先检查本地安装包，否则从wget下载JDK进行安装
install_JDK(){ 
        [ -d ${INSTALL_DIR} ] || mkdir -p ${INSTALL_DIR}
        cd ${INSTALL_DIR} 
        ls  | grep 'jdk.*[tar.gz]$'
        if [ $? -ne 0 ]; then
                echo '开始尝试从网络下载JDK.......'
                wget -P ${INSTALL_DIR}  ${JDKLINK}
         else
	echo "已在本地${INSTALL_DIR}下发现安装包"
        fi
        tar -zxf $(ls  | grep 'jdk.*[tar.gz]$')
        mv $(ls | grep 'jdk.*[^gz]$')  jdk1.8/
        echo "已在本地${INSTALL_DIR}下安装JDK完毕!"
}



#JDK环境变量配置
set_JDK_path(){
    echo "检查JDK环境变量中...."
	#PATH设置
	grep -q "export PATH=" /etc/profile
	if [ $? -ne 0 ]; then
		#末行插入
		echo 'export PATH=$PATH:$JAVA_HOME/bin'>>/etc/profile
	else
		#行尾添加
		sed -i '/^export PATH=.*/s/$/:\$JAVA_HOME\/bin/' /etc/profile
	fi
	grep -q "export JAVA_HOME=" /etc/profile
	if [ $? -ne 0 ]; then
		#导入配置
		filename="$(ls ${INSTALL_DIR}  | grep '^jdk.*[^rpm | gz]$' | sed -n '1p')"
		sed -i "/^export PATH=.*/i\export JAVA_HOME=\/opt\/software\/$filename" /etc/profile
		sed -i '/^export PATH=.*/i\export JRE_HOME=$JAVA_HOME/jre' /etc/profile
		sed -i '/^export PATH=.*/i\export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar' /etc/profile
		#echo "export JAVA_HOME=/opt/software/$filename">>/etc/profile
		#echo 'export JRE_HOME=$JAVA_HOME/jre'>>/etc/profile
		#echo 'export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar'>>/etc/profile
	else
		#替换原有配置
		filename="$(ls ${INSTALL_DIR} | grep '^jdk.*[^rpm | gz]$' | sed -n '1p')"
		sed -i "s/^export JAVA_HOME=.*/export JAVA_HOME=\/opt\/software\/$filename/" /etc/profile
	fi
	source /etc/profile
    echo "检查JDK环境变量完成!"
}

#优先检查本地安装包，否则从wget下载hadoop进行安装
install_hadoop(){
	cd ${INSTALL_DIR} 
	ls  | grep hadoop-2.6.5.tar.gz
	if [ $? -ne 0 ]; then
		echo '开始从网络中下载hadoop安装包...'
		wget $HADOOPLINK
	else
		echo "已在本地${INSTALL_DIR}下发现hadoop安装包"
	fi
	tar -zxf hadoop-2.6.5.tar.gz
	mv  hadoop-2.6.5  hadoop/
	echo  "已在本地${INSTALL_DIR}下安装hadoop完毕!"
}

#hadoop环境变量配置
set_hadoop_path(){
	echo "检查hadoop环境变量中...."
	#PATH设置
	grep -q "export PATH=" /etc/profile
	if [ $? -ne 0 ]; then
		#末行插入
		echo 'export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin'>>/etc/profile
	else
		#行尾添加
		sed -i '/^export PATH=.*/s/$/:\$HADOOP_HOME\/bin:\$HADOOP_HOME\/sbin/' /etc/profile
	fi
	#HADOOP_HOME设置
	grep -q "export HADOOP_HOME=" /etc/profile
	if [ $? -ne 0 ]; then
		#在PATH前面一行插入HADOOP_HOME
		sed -i '/^export PATH=.*/i\export HADOOP_HOME=\/opt\/software\/hadoop' /etc/profile
	else
		#修改文件内的HADOOP_HOME
		sed -i 's/^export HADOOP_HOME=.*/export HADOOP_HOME=\/opt\/software\/hadoop/' /etc/profile
	fi
	source /etc/profile
                echo "检查hadoop环境变量完成!"
}



#写入伪分布式配置信息
set_pseudo_distributed_model(){

echo 第一步配置core-site.xml
echo '<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<configuration>
	<property>
		<name>hadoop.tmp.dir</name>
		<value>file:/opt/software/hadoop/tmp</value>
		<description>指定hadoop运行时产生文件的存储路径</description>
	</property>
	<property>
		<name>fs.defaultFS</name>
		<value>hdfs://localhost:9000</value>
		<description>hdfs namenode的通信地址,通信端口</description>
	</property>
</configuration>' > /opt/software/hadoop/etc/hadoop/core-site.xml


echo 第二步配置hdfs-site.xml
echo '<?xml version="1.0" encoding="UTF-8"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!-- 该文件指定与HDFS相关的配置信息。
需要修改HDFS默认的块的副本属性，因为HDFS默认情况下每个数据块保存3个副本，
而在伪分布式模式下运行时，由于只有一个数据节点，
所以需要将副本个数改为1；否则Hadoop程序会报错。 -->
<configuration>
	<property>
		<name>dfs.replication</name>
		<value>1</value>
		<description>指定HDFS存储数据的副本数目，默认情况下是3份</description>
	</property>
	<property>
		<name>dfs.namenode.name.dir</name>
		<value>file:/opt/software/hadoop/hdfs/name</value>
		<description>namenode存放数据的目录</description>
	</property>
	<property>
		<name>dfs.datanode.data.dir</name>
		<value>file:/opt/software/hadoop/hdfs/data</value>
		<description>datanode存放block块的目录</description>
	</property>
	<property>
		<name>dfs.permissions.enabled</name>
		<value>false</value>
		<description>关闭权限验证</description>
	</property>
	  <property>
  		  <name>dfs.webhdfs.enabled</name>
  		  <value>true</value>
  	</property>
</configuration>'>/opt/software/hadoop/etc/hadoop/hdfs-site.xml


echo 第三步配置mapred-site.xml
echo '<?xml version="1.0"?>
<?xml-stylesheet type="text/xsl" href="configuration.xsl"?>
<!-- 在该配置文件中指定与MapReduce作业相关的配置属性，需要指定JobTracker运行的主机地址-->
<configuration>
	<property>
		<name>mapreduce.framework.name</name>
		<value>yarn</value>
		<description>指定mapreduce运行在yarn上</description>
	</property>
</configuration>'>/opt/software/hadoop/etc/hadoop/mapred-site.xml

echo 第四步配置yarn-site.xml
echo '<?xml version="1.0"?>
<configuration>
<!-- Site specific YARN configuration properties -->
	<property>stop
		<name>yarn.nodemanager.aux-services</name>
		<value>mapreduce_shuffle</value>
		<description>mapreduce执行shuffle时获取数据的方式</description>
	</property>
</configuration>'>/opt/software/hadoop/etc/hadoop/yarn-site.xml

echo 第五步配置hadoop-env.sh
echo 'export JAVA_HOME=/opt/software/jdk1.8/' >> /opt/software/hadoop/etc/hadoop/hadoop-env.sh
}




#SSH免密登录
local_ssh(){
	echo '---------------配置ssh免密登录----------------------'
	echo '------------连续输入三次回车即可生成秘钥-----------'
	ssh-keygen -t rsa
	echo '----------秘钥生成完成，开始生成公钥---------------'
	echo '根据提示输入相应的信息'
	echo '----------------------------------------------------'
	echo 'Are you sure you want to continue connecting (yes/no)?'
	echo '=========>输入"yes"<================'
	echo 'root@localhost password:'
	echo '=========>输入root用户密码<========='	
	ssh-copy-id localhost
}


#1、Java环境一键配置
java_mode_install(){
cd $INSTALL_DIR
echo '开始检查本机JDK'
jdk1.8/bin/javac 2>/dev/null
if [ $? -ne 2 ]; then
echo '检测到本机未安装JDK，开始安装，请耐心等待......'
#检查wget是否正常
install_wget			
#优先检查本地安装包，否则从wget下载JDK进行安装
install_JDK
#JDK环境变量配置
set_JDK_path
source /etc/profile
#检测安装结果
jdk1.8/bin/javac 2>/dev/null
if [ $? -eq 2 ]; then
echo 'JDK安装并配置完成，最后还需手动输入命令source /etc/profile进行刷新。'
else
echo '安装失败，请重新尝试或手动安装'
fi
else
echo '检测到本机JDK正常，无需操作'
fi
}

#2、hadoop本地模式一键安装
standalone_mode_install(){
java_mode_install
echo '开始检查本机hadoop环境'
hadoop/bin/hadoop 2>/dev/null
if [ $? -ne 0 ]; then
#优先检查本地安装包，否则从wget下载hadoop进行安装
install_hadoop
set_hadoop_path
#检测安装结果
hadoop/bin/hadoop 2>/dev/null
if [ $? -eq 0 ]; then
echo 'hadoop本地模式配置完成，最后还需手动输入命令source /etc/profile进行刷新。'
else
echo '安装失败，请重新尝试或手动安装'
fi
else
echo '检测到本机hadoop正常，无需操作'
fi
}

#3、Hadoop伪分布式一键安装
pseudo_distributed_mode_install(){

#设定静态ip为100  
ip_num2=100
#提取网段信息       
ip_num1=$(ip a | grep ens33 | awk '$1~/^inet.*/{print $2}' | awk -F '/' '{print $1}'|awk -F . '{print $3}')
echo 修改本地主机名为hadop100
hostnamectl set-hostname hadoop100
echo 修改网络配置文件 
#这部分顶格写
echo "TYPE="Ethernet"
BOOTPROTO="static"
DEVICE="ens33"
ONBOOT="yes"
IPADDR=192.168.${ip_num1}.${ip_num2}
NETMASK=255.255.255.0
GATEWAY=192.168.${ip_num1}.2
DNS1=223.5.5.5
DNS2=114.114.114.114" > /etc/sysconfig/network-scripts/ifcfg-ens33
echo 重启网络
systemctl restart network
local_IP=$(ip a | grep ens33 | awk '$1~/^inet.*/{print $2}' | awk -F '/' '{print $1}')    
echo "本机IP地址改动为${local_IP}"

standalone_mode_install
echo 写入伪分布式配置信息
set_pseudo_distributed_model
echo 开始关闭防火墙
systemctl stop firewalld
systemctl disable firewalld
echo 正在设置免密启动
local_ssh

echo '进行集群格式化！'
hadoop/bin/hdfs namenode -format
echo '伪分布式配置完成，最后还需手动输入命令source /etc/profile进行刷新！'



}


#控制台输入选项
consoleInput(){
	echo '1、Java环境一键配置'
	echo '2、Hadoop本地模式一键安装'
	echo '3、Hadoop伪分布式一键安装'
	echo '4、一键启动hadoop集群进程'
	echo '5、一键关闭hadoop集群进程'
	echo '请输入选项[1-10]'
	read aNum
	case $aNum in
        1)	java_mode_install
            ;;
        2)	standalone_mode_install
            ;;
        3)  pseudo_distributed_mode_install
            ;;
        4)	start-dfs.sh
         	start-yarn.sh
			jps
            ;;
        5)	stop-dfs.sh
        	stop-yarn.sh
			jps
            ;;          
        *)  echo '没有该选项，请重新输入!!!退出请按Ctrl+c'
                consoleInput
   			;;
    esac
    }
echo '------------------Hadoop生态一键安装------------------'
echo '请将该脚本命名为install.sh'
echo '请使用root用户执行该脚本'
echo '请将安装包放在/opt/software下'
echo '请确认安装包为.tar.gz结尾'
echo '如需进行集群搭建，请预先记录下所有节点ip地址'
echo '待增加功能：下载网址未更新'
echo '待增加功能：增加其他hadoop配置信息'
echo '待增加功能：hbase,zookeeper组件'
echo '------------------------------------------------------'
consoleInput
