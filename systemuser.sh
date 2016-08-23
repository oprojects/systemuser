#!/bin/sh

# Author: Danilo Piparo, Enric Tejedor 2016
# Copyright CERN
# Here the environment for the notebook server is prepared. Many of the commands are launched as regular 
# user as it's this entity which is able to access eos and not the super user.

# Create notebook user
# The $HOME directory is specified upstream in the Spawner
echo "Creating user $USER ($USER_ID)"
export CERNBOX_HOME=$HOME
useradd -u $USER_ID -s $SHELL -d $CERNBOX_HOME $USER
SCRATCH_HOME=/scratch/$USER
mkdir -p $SCRATCH_HOME
chown $USER:$USER $SCRATCH_HOME

# Setup the LCG View on CVMFS
echo "Setting up environment from CVMFS"
export LCG_VIEW=$ROOT_LCG_VIEW_PATH/$ROOT_LCG_VIEW_NAME/$ROOT_LCG_VIEW_PLATFORM

# Define default SWAN_HOME
export SWAN_HOME=$CERNBOX_HOME

# Set environment for the Jupyter process
echo "Setting Jupyter environment"
JPY_DIR=$SCRATCH_HOME/.jupyter
mkdir -p $JPY_DIR
JPY_LOCAL_DIR=$SCRATCH_HOME/.local
mkdir -p $JPY_LOCAL_DIR
export JUPYTER_CONFIG_DIR=$JPY_DIR
export JUPYTER_DATA_DIR=$JPY_LOCAL_DIR/share/jupyter
export JUPYTER_PATH=$JUPYTER_DATA_DIR
export KERNEL_DIR=$JUPYTER_PATH/kernels
mkdir -p $KERNEL_DIR
export JUPYTER_RUNTIME_DIR=$JUPYTER_DATA_DIR/runtime
export IPYTHONDIR=$SCRATCH_HOME/.ipython
JPY_CONFIG=$JPY_DIR/jupyter_notebook_config.py
echo "c.FileCheckpoints.checkpoint_dir = '$SCRATCH_HOME/.ipynb_checkpoints'" >> $JPY_CONFIG

# Configure kernels and terminal
# The environment of the kernels and the terminal will combine the view and the user script (if any)
echo "Configuring kernels and terminal"
cp -r  /usr/local/share/jupyter/kernelsBACKUP/python2 $KERNEL_DIR
cp -rL $LCG_VIEW/etc/notebook/kernels/root            $KERNEL_DIR 
cp -rL $LCG_VIEW/share/jupyter/kernels/*              $KERNEL_DIR
chown -R $USER:$USER $JPY_DIR $JPY_LOCAL_DIR
export SWAN_ENV_FILE=$SCRATCH_HOME/swan.sh
sudo -E -u $USER sh -c '   source $LCG_VIEW/setup.sh \
                        && export TMP_SCRIPT=`mktemp` \
                        && if [[ $USER_ENV_SCRIPT && -f `eval echo $USER_ENV_SCRIPT` ]]; \
                           then \
                             echo "Found user script: $USER_ENV_SCRIPT"; \
                             export TMP_SCRIPT=`mktemp`; \
                             cat `eval echo $USER_ENV_SCRIPT` > $TMP_SCRIPT; \
                             source $TMP_SCRIPT; \
                           else \
                             echo "Cannot find user script: $USER_ENV_SCRIPT"; \
                           fi \
                        && cd $KERNEL_DIR \
                        && python -c "import os; kdirs = os.listdir(\"./\"); \
                           kfile_names = [\"%s/kernel.json\" %kdir for kdir in kdirs]; \
                           kfile_contents = [open(kfile_name).read() for kfile_name in kfile_names]; \
                           exec(\"def addEnv(dtext): d=eval(dtext); d[\\\"env\\\"]=dict(os.environ); return d\"); \
                           kfile_contents_mod = map(addEnv, kfile_contents); \
                           import json; \
                           print kfile_contents_mod; \
                           map(lambda d: open(d[0],\"w\").write(json.dumps(d[1])), zip(kfile_names,kfile_contents_mod)); \
                           termEnvFile = open(\"$SWAN_ENV_FILE\", \"w\"); \
                           [termEnvFile.write(\"export %s=%s\\n\" % (key, val)) if key != \"SUDO_COMMAND\" else None for key, val in dict(os.environ).iteritems()];"'

# Make sure we have a sane terminal
printf "export TERM=xterm\n" >> $SWAN_ENV_FILE

# If there, source users' .bashrc after the SWAN environment
BASHRC_LOCATION=$SWAN_HOME/.bashrc
printf "if [[ -f $BASHRC_LOCATION ]];
then
   source $BASHRC_LOCATION
fi\n" >> $SWAN_ENV_FILE

if [ $? -ne 0 ]
then
  echo "Error setting the environment for kernels"
  exit 1
fi

# Set the terminal environment
export SWAN_BASH=/bin/swan_bash
printf "#! /bin/env python\nfrom subprocess import call\nimport sys\ncall([\"bash\", \"--rcfile\", \"$SWAN_ENV_FILE\"]+sys.argv[1:])\n" >> $SWAN_BASH
chmod +x $SWAN_BASH

# Overwrite link for python2 in the image
echo "Link Python"
ln -sf $LCG_VIEW/bin/python /usr/local/bin/python2

# Run notebook server
echo "Running the notebook server"
sudo -E -u $USER sh -c '   cd $SWAN_HOME \
                        && SHELL=$SWAN_BASH jupyterhub-singleuser \
                           --port=8888 \
                           --ip=0.0.0.0 \
                           --user=$JPY_USER \
                           --cookie-name=$JPY_COOKIE_NAME \
                           --base-url=$JPY_BASE_URL \
                           --hub-prefix=$JPY_HUB_PREFIX \
                           --hub-api-url=$JPY_HUB_API_URL'
