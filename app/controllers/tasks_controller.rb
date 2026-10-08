class TasksController < ApplicationController
  before_action :authenticate_user

  def index
    @tasks = Task.includes(:assignee)
  end

  def edit
    @task = Task.find(params[:id])
  end

  def create
    @task = Task.new(task_params)

    if @task.save
      redirect_to tasks_path
    else
      # TODO: handle
    end
  end

  def update
    @task = Task.find(params[:id])

    if @task.update(task_params)
      redirect_to tasks_path
    else
      # TODO: handle
    end
  end

  def destroy
    @task = Task.find(params[:id])

    if @task.destroy
      redirect_to tasks_path
    else
      # TODO: handle
    end
  end

  private

  def task_params
    params.require(:task).permit(:title, :description, :complete, :assignee_id)
  end
end
